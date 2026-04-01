"""Order routes — CRUD backed by Cloud SQL, events via Pub/Sub."""
import logging
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Header, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from db.database import get_db
from models.order import Order, OrderItem, OrderCreate, OrderOut, OrderStatus, OrderStatusUpdate
from messaging.pubsub import publish_order_event

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("", response_model=List[OrderOut])
async def list_orders(
    user_id:   str = Header(..., alias="x-user-id"),
    page:      int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    status_filter: Optional[OrderStatus] = Query(default=None, alias="status"),
    db: AsyncSession = Depends(get_db),
):
    q = (
        select(Order)
        .where(Order.user_id == user_id)
        .options(selectinload(Order.items))
        .order_by(Order.created_at.desc())
    )
    if status_filter:
        q = q.where(Order.status == status_filter)

    q = q.offset((page - 1) * page_size).limit(page_size)
    result = await db.execute(q)
    return result.scalars().all()


@router.get("/{order_id}", response_model=OrderOut)
async def get_order(
    order_id: str,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Order)
        .where(Order.id == order_id)
        .options(selectinload(Order.items))
    )
    order = result.scalar_one_or_none()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order


@router.post("", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
async def create_order(
    payload:  OrderCreate,
    user_id:  str = Header(..., alias="x-user-id"),
    db: AsyncSession = Depends(get_db),
):
    total = sum(item.unit_price * item.quantity for item in payload.items)

    order = Order(
        user_id=user_id,
        status=OrderStatus.pending,
        total_amount=round(total, 2),
        shipping_address=payload.shipping_address,
        payment_method=payload.payment_method,
        notes=payload.notes,
    )

    for item_data in payload.items:
        order.items.append(OrderItem(
            order_id=order.id,
            product_id=item_data.product_id,
            product_name=item_data.product_name,
            quantity=item_data.quantity,
            unit_price=item_data.unit_price,
            total_price=round(item_data.unit_price * item_data.quantity, 2),
        ))

    db.add(order)
    await db.flush()   # get the ID before commit

    # Publish event (fire-and-forget — don't fail order if PS is slow)
    try:
        await publish_order_event(
            order_id=order.id,
            user_id=user_id,
            event_type="placed",
            total_amount=order.total_amount,
            item_count=len(order.items),
        )
    except Exception as e:
        logger.warning({"msg": "Pub/Sub publish failed", "error": str(e), "order_id": order.id})

    logger.info({"action": "order_created", "order_id": order.id, "user_id": user_id})
    return order


@router.patch("/{order_id}/cancel", response_model=OrderOut)
async def cancel_order(
    order_id: str,
    user_id:  str = Header(..., alias="x-user-id"),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Order).where(Order.id == order_id).options(selectinload(Order.items))
    )
    order = result.scalar_one_or_none()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.user_id != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    if order.status not in (OrderStatus.pending, OrderStatus.confirmed):
        raise HTTPException(status_code=400, detail=f"Cannot cancel order in status '{order.status}'")

    order.status = OrderStatus.cancelled
    await db.flush()

    try:
        await publish_order_event(
            order_id=order.id,
            user_id=user_id,
            event_type="cancelled",
            total_amount=order.total_amount,
            item_count=len(order.items),
        )
    except Exception as e:
        logger.warning({"msg": "Pub/Sub publish failed", "error": str(e)})

    return order


@router.patch("/{order_id}/status", response_model=OrderOut)
async def update_order_status(
    order_id: str,
    payload:  OrderStatusUpdate,
    db: AsyncSession = Depends(get_db),
):
    """Admin-only endpoint — auth enforced at API Gateway."""
    result = await db.execute(
        select(Order).where(Order.id == order_id).options(selectinload(Order.items))
    )
    order = result.scalar_one_or_none()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.status = payload.status
    if payload.tracking_number:
        order.tracking_number = payload.tracking_number

    await db.flush()

    try:
        await publish_order_event(
            order_id=order.id,
            user_id=order.user_id,
            event_type=payload.status.value,
            total_amount=order.total_amount,
            item_count=len(order.items),
            metadata={"tracking_number": payload.tracking_number},
        )
    except Exception as e:
        logger.warning({"msg": "Pub/Sub publish failed", "error": str(e)})

    return order
