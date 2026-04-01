"""Order SQLAlchemy models and Pydantic schemas."""
import enum
from datetime import datetime
from typing import List, Optional
from uuid import uuid4

from sqlalchemy import (
    Column, String, Float, Integer, Enum as PgEnum,
    DateTime, ForeignKey, JSON, func,
)
from sqlalchemy.orm import relationship
from pydantic import BaseModel, Field

from db.database import Base


class OrderStatus(str, enum.Enum):
    pending    = "pending"
    confirmed  = "confirmed"
    processing = "processing"
    shipped    = "shipped"
    delivered  = "delivered"
    cancelled  = "cancelled"
    refunded   = "refunded"


# ── SQLAlchemy ORM ────────────────────────────────────────────

class OrderItem(Base):
    __tablename__ = "order_items"

    id          = Column(String, primary_key=True, default=lambda: str(uuid4()))
    order_id    = Column(String, ForeignKey("orders.id"), nullable=False)
    product_id  = Column(String, nullable=False)
    product_name= Column(String, nullable=False)
    quantity    = Column(Integer, nullable=False)
    unit_price  = Column(Float, nullable=False)
    total_price = Column(Float, nullable=False)

    order = relationship("Order", back_populates="items")


class Order(Base):
    __tablename__ = "orders"

    id              = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id         = Column(String, nullable=False, index=True)
    status          = Column(PgEnum(OrderStatus), nullable=False, default=OrderStatus.pending)
    total_amount    = Column(Float, nullable=False)
    currency        = Column(String, default="USD")
    shipping_address= Column(JSON, nullable=False)
    payment_method  = Column(String, nullable=False)
    payment_intent_id = Column(String, nullable=True)
    tracking_number = Column(String, nullable=True)
    notes           = Column(String, nullable=True)
    created_at      = Column(DateTime, server_default=func.now())
    updated_at      = Column(DateTime, server_default=func.now(), onupdate=func.now())

    items = relationship("OrderItem", back_populates="order", cascade="all, delete-orphan")


# ── Pydantic schemas ──────────────────────────────────────────

class OrderItemCreate(BaseModel):
    product_id:   str
    product_name: str
    quantity:     int   = Field(..., ge=1)
    unit_price:   float = Field(..., gt=0)


class OrderCreate(BaseModel):
    items:            List[OrderItemCreate]
    shipping_address: dict
    payment_method:   str
    notes:            Optional[str] = None


class OrderItemOut(BaseModel):
    id:           str
    product_id:   str
    product_name: str
    quantity:     int
    unit_price:   float
    total_price:  float

    model_config = {"from_attributes": True}


class OrderOut(BaseModel):
    id:               str
    user_id:          str
    status:           OrderStatus
    total_amount:     float
    currency:         str
    shipping_address: dict
    payment_method:   str
    tracking_number:  Optional[str]
    notes:            Optional[str]
    items:            List[OrderItemOut]
    created_at:       datetime
    updated_at:       datetime

    model_config = {"from_attributes": True}


class OrderStatusUpdate(BaseModel):
    status:          OrderStatus
    tracking_number: Optional[str] = None
