'use strict';

const express = require('express');
const multer  = require('multer');
const { Storage } = require('@google-cloud/storage');
const { v4: uuidv4 } = require('uuid');
const path = require('path');

const router  = express.Router();
const storage = new Storage();
const BUCKET  = process.env.GCS_BUCKET;

const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);
const MAX_SIZE_MB  = 10;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_SIZE_MB * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_MIME.has(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error(`Unsupported file type: ${file.mimetype}`));
    }
  },
});

// POST /api/v1/upload/product-image
// Returns the GCS public URL; Cloud Function will create thumbnails asynchronously
router.post('/product-image', upload.single('image'), async (req, res, next) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No image file provided' });
  }

  const ext      = path.extname(req.file.originalname).toLowerCase() || '.jpg';
  const filename = `products/${uuidv4()}${ext}`;
  const file     = storage.bucket(BUCKET).file(filename);

  try {
    await file.save(req.file.buffer, {
      metadata: {
        contentType: req.file.mimetype,
        cacheControl: 'public, max-age=31536000',
        metadata: {
          uploadedBy: req.user.sub,
          originalName: req.file.originalname,
        },
      },
    });

    const publicUrl = `https://storage.googleapis.com/${BUCKET}/${filename}`;

    res.status(201).json({
      url: publicUrl,
      filename,
      size: req.file.size,
      contentType: req.file.mimetype,
      // Thumbnail URLs will be available after Cloud Function processes the image
      thumbnails: {
        small:  publicUrl.replace(ext, `_sm${ext}`),
        medium: publicUrl.replace(ext, `_md${ext}`),
        large:  publicUrl.replace(ext, `_lg${ext}`),
      },
    });
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/upload/signed-url — for direct browser uploads
router.post('/signed-url', async (req, res, next) => {
  const { filename, contentType } = req.body;

  if (!filename || !contentType) {
    return res.status(400).json({ error: 'filename and contentType required' });
  }
  if (!ALLOWED_MIME.has(contentType)) {
    return res.status(400).json({ error: 'Unsupported content type' });
  }

  try {
    const ext  = path.extname(filename).toLowerCase();
    const key  = `products/${uuidv4()}${ext}`;
    const file = storage.bucket(BUCKET).file(key);

    const [signedUrl] = await file.generateSignedPostPolicyV4({
      expires: Date.now() + 15 * 60 * 1000, // 15 minutes
      conditions: [
        ['content-length-range', 0, MAX_SIZE_MB * 1024 * 1024],
        ['eq', '$Content-Type', contentType],
      ],
      fields: { 'Content-Type': contentType },
    });

    res.json({ signedUrl, key, publicUrl: `https://storage.googleapis.com/${BUCKET}/${key}` });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
