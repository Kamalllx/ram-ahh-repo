"""Cloud SQL (PostgreSQL) async engine via Cloud SQL Python Connector."""
import os
from google.cloud.sql.connector import AsyncConnector, IPTypes
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker
import asyncpg

connector = AsyncConnector()

DB_CONNECTION_NAME = os.environ["DB_CONNECTION_NAME"]   # project:region:instance
DB_USER            = os.environ["DB_USER"]
DB_PASS            = os.environ["DB_PASS"]
DB_NAME            = os.environ["DB_NAME"]


async def get_conn() -> asyncpg.Connection:
    return await connector.connect_async(
        DB_CONNECTION_NAME,
        "asyncpg",
        user=DB_USER,
        password=DB_PASS,
        db=DB_NAME,
        ip_type=IPTypes.PRIVATE,
    )


engine = create_async_engine(
    "postgresql+asyncpg://",
    async_creator=get_conn,
    pool_size=5,
    max_overflow=10,
    pool_pre_ping=True,
    echo=os.getenv("LOG_SQL") == "1",
)

AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
