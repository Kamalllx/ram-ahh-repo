"""
CloudMart Order Service
Runs on GKE. Stores orders in Cloud SQL (PostgreSQL). Publishes events to Pub/Sub.
"""
import os
import logging

import google.cloud.logging
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager

from db.database import engine, Base
from routes.orders import router as orders_router

if os.getenv("KUBERNETES_SERVICE_HOST"):
    google.cloud.logging.Client().setup_logging()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create tables on startup if they don't exist
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database tables ready")
    yield
    await engine.dispose()


app = FastAPI(
    title="CloudMart Order Service",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if os.getenv("ENVIRONMENT") != "prod" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def global_handler(request: Request, exc: Exception):
    logger.error({"error": str(exc), "path": request.url.path}, exc_info=True)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


app.include_router(orders_router, prefix="/orders", tags=["orders"])


@app.get("/health")
async def health():
    from sqlalchemy import text
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        db_status = "ok"
    except Exception as e:
        logger.warning(f"DB health check failed: {e}")
        db_status = "degraded"

    return {
        "status": "ok" if db_status == "ok" else "degraded",
        "service": "order-service",
        "version": "1.0.0",
        "checks": {"database": db_status},
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, workers=4)
