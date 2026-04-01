"""Product data models (Pydantic v2)."""
from __future__ import annotations

from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field, field_validator
from uuid import uuid4


class ProductImage(BaseModel):
    url: str
    alt: str = ""
    width: Optional[int] = None
    height: Optional[int] = None


class ProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: str = Field(..., min_length=1, max_length=5000)
    price: float = Field(..., gt=0)
    category: str
    tags: List[str] = []
    images: List[ProductImage] = []
    stock_quantity: int = Field(default=0, ge=0)
    sku: Optional[str] = None

    @field_validator("price")
    @classmethod
    def round_price(cls, v: float) -> float:
        return round(v, 2)


class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=5000)
    price: Optional[float] = Field(None, gt=0)
    category: Optional[str] = None
    tags: Optional[List[str]] = None
    images: Optional[List[ProductImage]] = None
    stock_quantity: Optional[int] = Field(None, ge=0)
    is_active: Optional[bool] = None


class Product(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    name: str
    description: str
    price: float
    category: str
    tags: List[str] = []
    images: List[ProductImage] = []
    stock_quantity: int = 0
    sku: Optional[str] = None
    is_active: bool = True
    rating_avg: float = 0.0
    rating_count: int = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    @classmethod
    def from_firestore(cls, doc_id: str, data: dict) -> "Product":
        data["id"] = doc_id
        # Firestore DatetimeWithNanoseconds → datetime
        for field in ("created_at", "updated_at"):
            if hasattr(data.get(field), "timestamp"):
                data[field] = data[field].datetime_pb
        return cls(**data)


class ProductListResponse(BaseModel):
    items: List[Product]
    total: int
    page: int
    page_size: int
    has_next: bool
