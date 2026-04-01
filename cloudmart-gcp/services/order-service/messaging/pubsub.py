"""Pub/Sub publisher for order lifecycle events."""
import json
import logging
import os
from datetime import datetime

from google.cloud import pubsub_v1

logger = logging.getLogger(__name__)

PROJECT_ID  = os.environ["GCP_PROJECT"]
TOPIC_NAME  = os.environ["PUBSUB_TOPIC"]
TOPIC_PATH  = f"projects/{PROJECT_ID}/topics/{TOPIC_NAME}"

publisher = pubsub_v1.PublisherClient()


async def publish_order_event(
    order_id: str,
    user_id: str,
    event_type: str,
    total_amount: float,
    item_count: int,
    metadata: dict | None = None,
) -> str:
    """Publish an order event to Pub/Sub. Returns message ID."""

    payload = {
        "order_id":     order_id,
        "user_id":      user_id,
        "event_type":   event_type,   # placed | confirmed | shipped | delivered | cancelled
        "total_amount": total_amount,
        "item_count":   item_count,
        "timestamp":    datetime.utcnow().isoformat(),
        "metadata":     json.dumps(metadata or {}),
    }

    data    = json.dumps(payload).encode("utf-8")
    attrs   = {
        "event_type": event_type,
        "order_id":   order_id,
    }

    future = publisher.publish(TOPIC_PATH, data, **attrs)
    msg_id = future.result(timeout=10)
    logger.info({"action": "pubsub_published", "event": event_type, "order_id": order_id, "msg_id": msg_id})
    return msg_id
