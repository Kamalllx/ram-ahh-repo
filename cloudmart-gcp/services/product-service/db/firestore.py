"""Firestore client singleton."""
import os
from google.cloud import firestore

# Async Firestore client (uses grpc under the hood)
firestore_client: firestore.AsyncClient = firestore.AsyncClient(
    project=os.getenv("GCP_PROJECT"),
)

PRODUCTS_COLLECTION = "products"
CATEGORIES_COLLECTION = "categories"
