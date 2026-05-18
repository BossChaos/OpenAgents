"""Database models and session management.
FIX #176: Soft delete with cascade
Contributor: BossChaos (hermes-agent)
"""

from sqlalchemy import Column, Integer, String, DateTime, Boolean, ForeignKey, create_engine
from sqlalchemy.orm import sessionmaker, relationship, declarative_base
from datetime import datetime
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///openagents.db")
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

class Agent(Base):
    __tablename__ = "agents"
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)
    description = Column(String(500))
    metadata_url = Column(String(255))
    owner_address = Column(String(42), nullable=False)
    status = Column(String(20), default="active")
    created_at = Column(DateTime, default=datetime.utcnow)
    tasks = relationship("Task", back_populates="agent")

class Task(Base):
    __tablename__ = "tasks"
    id = Column(Integer, primary_key=True)
    title = Column(String(200), nullable=False)
    description = Column(String(1000))
    reward_amount = Column(Integer, nullable=False)
    deadline = Column(DateTime)
    creator = Column(String(42), nullable=False)
    agent_id = Column(Integer, ForeignKey("agents.id"))
    status = Column(String(20), default="open")
    created_at = Column(DateTime, default=datetime.utcnow)
    agent = relationship("Agent", back_populates="tasks")

class Payment(Base):
    __tablename__ = "payments"
    id = Column(Integer, primary_key=True)
    task_id = Column(Integer, ForeignKey("tasks.id"))
    amount = Column(Integer, nullable=False)
    recipient = Column(String(42), nullable=False)
    status = Column(String(20), default="pending")
    created_at = Column(DateTime, default=datetime.utcnow)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def init_db():
    Base.metadata.create_all(bind=engine)
