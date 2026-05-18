"""Database models and connection management for the OpenAgents API."""

from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, BigInteger, ForeignKey, Index
from sqlalchemy.orm import sessionmaker, declarative_base, Session
from contextlib import contextmanager
import os
from typing import Generator

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///openagents.db")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
Base = declarative_base()


class Agent(Base):
    __tablename__ = "agents"

    id = Column(Integer, primary_key=True, index=True)
    agent_id = Column(String, unique=True, nullable=False, index=True)
    name = Column(String, nullable=False)
    owner = Column(String, nullable=False, index=True)
    endpoint = Column(String, nullable=False)
    reputation = Column(Integer, default=0)
    tasks_completed = Column(Integer, default=0)
    registered_at = Column(DateTime, nullable=False)
    active = Column(Integer, default=1)

    # FIX: Add composite indexes for common query patterns
    __table_args__ = (
        Index("idx_agent_reputation_active", "reputation", "active"),
        Index("idx_agent_owner_active", "owner", "active"),
    )


class Task(Base):
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=False)
    reward_amount = Column(Float, nullable=False)
    creator_id = Column(String, nullable=False, index=True)
    agent_id = Column(Integer, ForeignKey("agents.id"), index=True)
    status = Column(String, default="open", index=True)
    created_at = Column(DateTime, nullable=False, index=True)
    deadline = Column(DateTime, nullable=True)
    updated_at = Column(DateTime, nullable=True)

    # FIX: Add composite indexes for filtering and pagination
    __table_args__ = (
        Index("idx_task_status_created", "status", "created_at"),
        Index("idx_task_creator_status", "creator_id", "status"),
    )


class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, index=True)
    task_id = Column(Integer, ForeignKey("tasks.id"), nullable=False, index=True)
    from_address = Column(String, nullable=False, index=True)
    to_address = Column(String, nullable=False, index=True)
    amount_wei = Column(BigInteger, nullable=False)
    status = Column(String, default="pending", index=True)
    created_at = Column(DateTime, nullable=False)
    confirmed_at = Column(DateTime, nullable=True)
    tx_hash = Column(String, unique=True, nullable=True)

    # FIX: Add composite index for payment queries
    __table_args__ = (
        Index("idx_payment_task_status", "task_id", "status"),
        Index("idx_payment_from_created", "from_address", "created_at"),
    )


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    Base.metadata.create_all(bind=engine)
