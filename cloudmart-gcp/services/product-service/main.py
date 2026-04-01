"""
CloudMart Product Service
Runs on GKE. Stores product catalog in Firestore.
"""
import os
import logging

import google.cloud.logging
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from routes.products import router as products_router
from db.firestore import firestore_client

# ── Google Cloud Logging ──────────────────────────────────────
if os.getenv("K_SERVICE") or os.getenv("KUBERNETES_SERVICE_HOST"):
    cloud_logging_client = google.cloud.logging.Client()
    cloud_logging_client.setup_logging()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── App ───────────────────────────────────────────────────────
app = FastAPI(
    title="CloudMart Product Service",
    version="1.0.0",
    docs_url="/docs" if os.getenv("ENVIRONMENT") != "prod" else None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info({"method": request.method, "path": request.url.path})
    response = await call_next(request)
    logger.info({"status": response.status_code, "path": request.url.path})
    return response

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error({"error": str(exc), "path": request.url.path}, exc_info=True)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})

# ── Routes ────────────────────────────────────────────────────
app.include_router(products_router, prefix="/products", tags=["products"])

@app.get("/health")
async def health():
    try:
        # Verify Firestore connectivity
        await firestore_client.collection("_health").limit(1).get()
        db_status = "ok"
    except Exception as e:
        logger.warning(f"Firestore health check failed: {e}")
        db_status = "degraded"

    return {
        "status": "ok" if db_status == "ok" else "degraded",
        "service": "product-service",
        "version": "1.0.0",
        "checks": {"firestore": db_status},
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=False, workers=4)
