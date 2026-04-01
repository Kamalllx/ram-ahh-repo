"""
Cloud Function: Order Notifier
Trigger: Pub/Sub message on orders topic
Action:  Sends order confirmation / shipping notification emails
         (Uses SendGrid or SMTP — configured via Secret Manager)
"""
import base64
import json
import logging
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from google.cloud import secretmanager

logger = logging.getLogger(__name__)

secret_client = secretmanager.SecretManagerServiceClient()
GCP_PROJECT   = os.environ["GCP_PROJECT"]


def _get_secret(name: str) -> str:
    resource = f"projects/{GCP_PROJECT}/secrets/{name}/versions/latest"
    response = secret_client.access_secret_version(request={"name": resource})
    return response.payload.data.decode("utf-8")


EMAIL_TEMPLATES = {
    "placed": {
        "subject": "Order Confirmed — CloudMart #{order_id}",
        "body": """\
Hi {user_id},

Your order #{order_id} has been placed successfully!

Items: {item_count}
Total: ${total_amount:.2f}

We'll send you another email when your order ships.

Thanks for shopping with CloudMart!
""",
    },
    "shipped": {
        "subject": "Your CloudMart order #{order_id} has shipped!",
        "body": """\
Great news! Your CloudMart order #{order_id} is on its way.

Items: {item_count}
Total: ${total_amount:.2f}

You'll receive a tracking number shortly.

Thanks for your patience!
""",
    },
    "delivered": {
        "subject": "CloudMart order #{order_id} delivered!",
        "body": """\
Your CloudMart order #{order_id} has been delivered.

We hope you enjoy your purchase! Please leave a review.

CloudMart Team
""",
    },
}


def notify_order(cloud_event, context=None):
    """Entry point for Pub/Sub triggered Cloud Function."""
    # Decode Pub/Sub message
    pubsub_message = cloud_event.data.get("message", {})
    if not pubsub_message:
        logger.warning("No Pub/Sub message in event")
        return

    raw  = base64.b64decode(pubsub_message.get("data", "")).decode("utf-8")
    data = json.loads(raw)

    event_type   = data.get("event_type")
    order_id     = data.get("order_id")
    user_id      = data.get("user_id")
    total_amount = data.get("total_amount", 0.0)
    item_count   = data.get("item_count", 0)

    logger.info({"event": event_type, "order_id": order_id, "user_id": user_id})

    template = EMAIL_TEMPLATES.get(event_type)
    if not template:
        logger.info(f"No email template for event type: {event_type}")
        return

    subject = template["subject"].format(order_id=order_id[:8].upper())
    body    = template["body"].format(
        user_id=user_id,
        order_id=order_id[:8].upper(),
        total_amount=float(total_amount),
        item_count=item_count,
    )

    _send_email(
        to_addr=os.environ.get("NOTIFICATION_EMAIL", "orders@cloudmart.demo"),
        subject=subject,
        body=body,
    )

    logger.info({"action": "email_sent", "event": event_type, "order_id": order_id})
    return {"sent": True, "event": event_type}


def _send_email(to_addr: str, subject: str, body: str):
    """Send email via SMTP. In production, swap for SendGrid/Mailgun."""
    try:
        smtp_host = os.environ.get("SMTP_HOST", "smtp.gmail.com")
        smtp_port = int(os.environ.get("SMTP_PORT", "587"))
        smtp_user = _get_secret("cloudmart-smtp-user")
        smtp_pass = _get_secret("cloudmart-smtp-password")

        msg           = MIMEMultipart("alternative")
        msg["Subject"]= subject
        msg["From"]   = f"CloudMart <{smtp_user}>"
        msg["To"]     = to_addr
        msg.attach(MIMEText(body, "plain"))

        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.starttls()
            server.login(smtp_user, smtp_pass)
            server.sendmail(smtp_user, [to_addr], msg.as_string())

    except Exception as e:
        # Don't fail the function on email errors — log and move on
        logger.error({"msg": "Email send failed", "error": str(e), "to": to_addr})
