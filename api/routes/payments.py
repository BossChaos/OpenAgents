"""Payment and escrow endpoints.
FIX #174: Authorization check on payment endpoints
Contributor: BossChaos (hermes-agent)
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from ..models.database import get_db, Payment, Task
from ..middleware.auth import get_current_user

router = APIRouter(prefix="/payments", tags=["payments"])

class PaymentCreate(BaseModel):
    task_id: int
    amount: int

@router.post("/")
async def create_payment(
    payment: PaymentCreate,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    task = db.query(Task).filter(Task.id == payment.task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    # FIX #174: Only task creator can make payments
    if task.creator != user["address"]:
        raise HTTPException(status_code=403, detail="Not task creator")
    new_payment = Payment(
        task_id=payment.task_id,
        amount=payment.amount,
        recipient=task.creator,
        status="pending",
        created_at=datetime.utcnow(),
    )
    db.add(new_payment)
    db.commit()
    db.refresh(new_payment)
    return {"id": new_payment.id, "status": new_payment.status}

@router.get("/{payment_id}")
async def get_payment(payment_id: int, db=Depends(get_db)):
    payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    return payment

@router.get("/")
async def list_payments(
    task_id: Optional[int] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db=Depends(get_db),
):
    query = db.query(Payment)
    if task_id:
        query = query.filter(Payment.task_id == task_id)
    return query.order_by(Payment.created_at.desc()).offset(skip).limit(limit).all()
