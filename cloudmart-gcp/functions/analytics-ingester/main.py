"""
Cloud Function: Analytics Ingester
Trigger: Cloud Scheduler → Pub/Sub (nightly at 2 AM)
Action:  Syncs yesterday's orders from Cloud SQL to BigQuery for analytics
"""
import base64
import json
import logging
import os
from datetime import datetime, timedelta, timezone

import asyncpg
from google.cloud import bigquery
from google.cloud.sql.connector import Connector

logger = logging.getLogger(__name__)

GCP_PROJECT   = os.environ["GCP_PROJECT"]
BQ_DATASET    = os.environ["BQ_DATASET"]
BQ_TABLE      = os.environ["BQ_TABLE"]
DB_CONNECTION = os.environ.get("DB_CONNECTION_NAME")
DB_USER       = os.environ.get("DB_USER", "cloudmart_admin")
DB_PASS       = os.environ.get("DB_PASS", "")
DB_NAME       = os.environ.get("DB_NAME", "cloudmart")

bq_client = bigquery.Client(project=GCP_PROJECT)


async def _fetch_orders(date_from: datetime, date_to: datetime) -> list[dict]:
    connector = Connector()
    try:
        conn = await connector.connect_async(
            DB_CONNECTION,
            "asyncpg",
            user=DB_USER,
            password=DB_PASS,
            db=DB_NAME,
        )
        rows = await conn.fetch(
            """
            SELECT
                o.id              AS order_id,
                o.user_id,
                o.total_amount,
                o.status,
                COUNT(oi.id)      AS item_count,
                o.created_at,
                'us-central1'     AS region
            FROM orders o
            JOIN order_items oi ON oi.order_id = o.id
            WHERE o.created_at >= $1 AND o.created_at < $2
            GROUP BY o.id, o.user_id, o.total_amount, o.status, o.created_at
            ORDER BY o.created_at
            """,
            date_from,
            date_to,
        )
        await conn.close()
        return [dict(row) for row in rows]
    finally:
        await connector.close_async()


def ingest_analytics(cloud_event, context=None):
    """Entry point — triggered by Cloud Scheduler via Pub/Sub."""
    import asyncio

    pubsub_message = cloud_event.data.get("message", {})
    raw  = base64.b64decode(pubsub_message.get("data", "e30=")).decode("utf-8")
    data = json.loads(raw)

    # Support manual override of date range
    if "date_from" in data:
        date_from = datetime.fromisoformat(data["date_from"]).replace(tzinfo=timezone.utc)
        date_to   = datetime.fromisoformat(data["date_to"]).replace(tzinfo=timezone.utc)
    else:
        today     = datetime.now(tz=timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        date_from = today - timedelta(days=1)
        date_to   = today

    logger.info({"action": "analytics_ingest_start", "from": str(date_from), "to": str(date_to)})

    rows = asyncio.run(_fetch_orders(date_from, date_to))

    if not rows:
        logger.info("No orders found for date range")
        return {"rows_inserted": 0}

    # Convert for BigQuery
    bq_rows = [
        {
            "order_id":     row["order_id"],
            "user_id":      row["user_id"],
            "total_amount": float(row["total_amount"]),
            "status":       row["status"],
            "item_count":   int(row["item_count"]),
            "created_at":   row["created_at"].isoformat(),
            "region":       row["region"],
        }
        for row in rows
    ]

    table_ref = f"{GCP_PROJECT}.{BQ_DATASET}.{BQ_TABLE}"
    errors    = bq_client.insert_rows_json(table_ref, bq_rows)

    if errors:
        logger.error({"msg": "BigQuery insert errors", "errors": errors})
        raise RuntimeError(f"BigQuery errors: {errors}")

    logger.info({
        "action":        "analytics_ingest_complete",
        "rows_inserted": len(bq_rows),
        "date_from":     str(date_from),
        "date_to":       str(date_to),
    })
    return {"rows_inserted": len(bq_rows)}
