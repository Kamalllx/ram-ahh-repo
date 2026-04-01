"""
Cloud Function: Image Processor
Trigger: GCS object finalized (new upload to images bucket)
Action:  Creates thumbnail (200x200), medium (600x600), and large (1200x1200) variants
"""
import io
import os
import logging
from pathlib import Path

from google.cloud import storage
from PIL import Image, ImageOps

logger = logging.getLogger(__name__)

storage_client = storage.Client()

SIZES = {
    "sm": (200, 200),
    "md": (600, 600),
    "lg": (1200, 1200),
}


def process_image(cloud_event, context=None):
    """Entry point — called by Cloud Functions framework."""
    data    = cloud_event.data
    bucket  = data["bucket"]
    name    = data["name"]

    # Skip already-processed variants to avoid infinite loop
    stem = Path(name).stem
    if any(stem.endswith(f"_{size}") for size in SIZES):
        logger.info(f"Skipping already-processed file: {name}")
        return

    ext = Path(name).suffix.lower()
    if ext not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
        logger.info(f"Skipping non-image file: {name}")
        return

    logger.info(f"Processing image: gs://{bucket}/{name}")

    source_bucket = storage_client.bucket(bucket)
    blob          = source_bucket.blob(name)

    # Download original
    image_bytes = blob.download_as_bytes()
    img = Image.open(io.BytesIO(image_bytes))

    # Preserve EXIF orientation
    img = ImageOps.exif_transpose(img)

    # Convert to RGB if needed (PNG with transparency → JPEG-compatible)
    if img.mode in ("RGBA", "P"):
        background = Image.new("RGB", img.size, (255, 255, 255))
        if img.mode == "P":
            img = img.convert("RGBA")
        background.paste(img, mask=img.split()[3] if img.mode == "RGBA" else None)
        img = background

    base_name    = Path(name).with_suffix("").as_posix()
    output_ext   = ext if ext != ".gif" else ".jpg"
    pil_format   = "JPEG" if output_ext in (".jpg", ".jpeg") else "PNG"
    content_type = f"image/{'jpeg' if pil_format == 'JPEG' else 'png'}"

    for size_name, (w, h) in SIZES.items():
        resized     = img.copy()
        resized.thumbnail((w, h), Image.LANCZOS)

        buf = io.BytesIO()
        resized.save(buf, format=pil_format, quality=85, optimize=True)
        buf.seek(0)

        dest_name = f"{base_name}_{size_name}{output_ext}"
        dest_blob = source_bucket.blob(dest_name)
        dest_blob.upload_from_file(buf, content_type=content_type)
        dest_blob.cache_control = "public, max-age=31536000"
        dest_blob.patch()

        logger.info(f"Created: gs://{bucket}/{dest_name} ({w}x{h})")

    logger.info(f"Image processing complete for: {name}")
    return {"processed": name, "variants": list(SIZES.keys())}
