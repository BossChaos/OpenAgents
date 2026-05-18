"""Task/bounty management endpoints.
FIX #159: Input validation for task creation
Contributor: BossChaos (hermes-agent)
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator
from typing import Optional
from datetime import datetime, timedelta
from ..models.database import get_db, Task
from ..middleware.auth import get_current_user

router = APIRouter(prefix="/tasks", tags=["tasks"])

class TaskCreate(BaseModel):
    title: str
    description: str
    reward_amount: int
    deadline_days: int = 30

    @field_validator('title')
    @classmethod
    def validate_title(cls, v):
        if len(v.strip()) < 5:
            raise ValueError("Title must be at least 5 characters")
        if len(v) > 200:
            raise ValueError("Title too long")
        return v.strip()

    @field_validator('reward_amount')
    @classmethod
    def validate_reward(cls, v):
        if v <= 0:
            raise ValueError("Reward must be positive")
        if v > 1_000_000:
            raise ValueError("Reward exceeds maximum")
        return v

    @field_validator('deadline_days')
    @classmethod
    def validate_deadline(cls, v):
        if v < 1 or v > 365:
            raise ValueError("Deadline must be 1-365 days")
        return v

@router.post("/")
async def create_task(task: TaskCreate, user=Depends(get_current_user), db=Depends(get_db)):
    new_task = Task(
        title=task.title,
        description=task.description,
        reward_amount=task.reward_amount,
        deadline=datetime.utcnow() + timedelta(days=task.deadline_days),
        creator=user.get("address"),
        status="open",
        created_at=datetime.utcnow(),
    )
    db.add(new_task)
    db.commit()
    db.refresh(new_task)
    return {"id": new_task.id, "status": "created"}

@router.get("/")
async def list_tasks(
    status: Optional[str] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db=Depends(get_db),
):
    query = db.query(Task)
    if status:
        query = query.filter(Task.status == status)
    return query.order_by(Task.created_at.desc()).offset(skip).limit(limit).all()
