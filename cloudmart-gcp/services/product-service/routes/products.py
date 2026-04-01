"""Product CRUD routes backed by Firestore."""
import logging
from typing import Optional, List

from fastapi import APIRouter, HTTPException, Query, status
from google.cloud.firestore_v1.base_query import FieldFilter

from db.firestore import firestore_client, PRODUCTS_COLLECTION
from models.product import Product, ProductCreate, ProductUpdate, ProductListResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("", response_model=ProductListResponse)
async def list_products(
    category: Optional[str] = None,
    min_price: Optional[float] = None,
    max_price: Optional[float] = None,
    in_stock: bool = False,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    col = firestore_client.collection(PRODUCTS_COLLECTION)
    query = col.where(filter=FieldFilter("is_active", "==", True))

    if category:
        query = query.where(filter=FieldFilter("category", "==", category))
    if min_price is not None:
        query = query.where(filter=FieldFilter("price", ">=", min_price))
    if max_price is not None:
        query = query.where(filter=FieldFilter("price", "<=", max_price))
    if in_stock:
        query = query.where(filter=FieldFilter("stock_quantity", ">", 0))

    query = query.order_by("created_at", direction="DESCENDING")

    # Count total (Firestore doesn't support COUNT natively, so we paginate)
    all_docs = [doc async for doc in query.stream()]
    total = len(all_docs)

    offset = (page - 1) * page_size
    page_docs = all_docs[offset:offset + page_size]

    items = [Product.from_firestore(doc.id, doc.to_dict()) for doc in page_docs]

    return ProductListResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        has_next=(offset + page_size) < total,
    )


@router.get("/search", response_model=ProductListResponse)
async def search_products(
    q: str = Query(..., min_length=1),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    # Firestore full-text search via prefix match on name
    # In production, use Algolia or Elastic for proper full-text search
    col = firestore_client.collection(PRODUCTS_COLLECTION)
    q_lower = q.lower()

    query = (
        col
        .where(filter=FieldFilter("is_active", "==", True))
        .where(filter=FieldFilter("name_lower", ">=", q_lower))
        .where(filter=FieldFilter("name_lower", "<=", q_lower + "\uf8ff"))
        .limit(100)
    )

    docs = [doc async for doc in query.stream()]
    total = len(docs)
    offset = (page - 1) * page_size
    items = [Product.from_firestore(doc.id, doc.to_dict()) for doc in docs[offset:offset + page_size]]

    return ProductListResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        has_next=(offset + page_size) < total,
    )


@router.get("/{product_id}", response_model=Product)
async def get_product(product_id: str):
    doc = await firestore_client.collection(PRODUCTS_COLLECTION).document(product_id).get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Product not found")
    return Product.from_firestore(doc.id, doc.to_dict())


@router.post("", response_model=Product, status_code=status.HTTP_201_CREATED)
async def create_product(payload: ProductCreate):
    from datetime import datetime
    product = Product(
        **payload.model_dump(),
        name_lower=payload.name.lower(),
    )
    data = product.model_dump()
    data["created_at"] = datetime.utcnow()
    data["updated_at"] = datetime.utcnow()

    await firestore_client.collection(PRODUCTS_COLLECTION).document(product.id).set(data)
    logger.info({"action": "product_created", "product_id": product.id})
    return product


@router.put("/{product_id}", response_model=Product)
async def update_product(product_id: str, payload: ProductUpdate):
    from datetime import datetime
    ref = firestore_client.collection(PRODUCTS_COLLECTION).document(product_id)
    doc = await ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Product not found")

    updates = payload.model_dump(exclude_none=True)
    if "name" in updates:
        updates["name_lower"] = updates["name"].lower()
    updates["updated_at"] = datetime.utcnow()

    await ref.update(updates)
    updated = await ref.get()
    return Product.from_firestore(updated.id, updated.to_dict())


@router.delete("/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_product(product_id: str):
    ref = firestore_client.collection(PRODUCTS_COLLECTION).document(product_id)
    doc = await ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Product not found")

    # Soft delete
    await ref.update({"is_active": False})
    logger.info({"action": "product_deleted", "product_id": product_id})
