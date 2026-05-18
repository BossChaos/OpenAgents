"""Payment and escrow management endpoints."""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from enum import Enum

from ..models.database import get_db, Payment
from ..middleware.auth import get_current_user

router = APIRouter(prefix="/payments", tags=["payments"])


# FIX: Structured error response model with error codes
class ErrorCode(str, Enum):
    PAYMENT_NOT_FOUND = "PAYMENT_NOT_FOUND"
    INVALID_AMOUNT = "INVALID_AMOUNT"
    INSUFFICIENT_BALANCE = "INSUFFICIENT_BALANCE"
    DUPLICATE_PAYMENT = "DUPLICATE_PAYMENT"
    PAYMENT_EXPIRED = "PAYMENT_EXPIRED"
    UNAUTHORIZED = "UNAUTHORIZED"
    INTERNAL_ERROR = "INTERNAL_ERROR"


class ErrorResponse(BaseModel):
    success: bool = False
    error: ErrorCode
    message: str
    code: str
    details: Optional[dict] = None
    timestamp: str


class SuccessResponse(BaseModel):
    success: bool = True
    data: dict
    timestamp: str


class PaymentCreate(BaseModel):
    task_id: int
    to_address: str
    amount_wei: int


class PaymentResponse(BaseModel):
    id: int
    task_id: int
    from_address: str
    to_address: str
    amount_wei: int
    status: str
    created_at: datetime
    confirmed_at: Optional[datetime] = None
    tx_hash: Optional[str] = None


@router.post("/")
async def create_payment(
    payment: PaymentCreate,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    if payment.amount_wei <= 0:
        raise HTTPException(
            status_code=400,
            detail={
                "success": False,
                "error": ErrorCode.INVALID_AMOUNT.value,
                "message": "Payment amount must be greater than zero",
                "code": ErrorCode.INVALID_AMOUNT,
            },
        )

    existing = db.query(Payment).filter(
        Payment.task_id == payment.task_id,
        Payment.from_address == user["address"],
        Payment.status == "pending",
    ).first()
    if existing:
        raise HTTPException(
            status_code=409,
            detail={
                "success": False,
                "error": ErrorCode.DUPLICATE_PAYMENT.value,
                "message": "Pending payment already exists for this task",
                "code": ErrorCode.DUPLICATE_PAYMENT,
            },
        )

    new_payment = Payment(
        task_id=payment.task_id,
        from_address=user["address"],
        to_address=payment.to_address,
        amount_wei=payment.amount_wei,
        status="pending",
        created_at=datetime.utcnow(),
    )
    db.add(new_payment)
    db.commit()
    db.refresh(new_payment)
    return {
        "success": True,
        "data": {
            "id": new_payment.id,
            "status": new_payment.status,
            "amount_wei": new_payment.amount_wei,
        },
        "timestamp": datetime.utcnow().isoformat(),
    }


@router.get("/", response_model=List[PaymentResponse])
async def list_payments(
    status: Optional[str] = None,
    from_address: Optional[str] = None,
    task_id: Optional[int] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db=Depends(get_db),
):
    query = db.query(Payment)
    if status:
        query = query.filter(Payment.status == status)
    if from_address:
        query = query.filter(Payment.from_address == from_address)
    if task_id:
        query = query.filter(Payment.task_id == task_id)
    return query.order_by(Payment.created_at.desc()).offset(skip).limit(limit).all()


@router.get("/{payment_id}")
async def get_payment(payment_id: int, db=Depends(get_db)):
    payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(
            status_code=404,
            detail={
                "success": False,
                "error": ErrorCode.PAYMENT_NOT_FOUND.value,
                "message": "Payment not found",
                "code": ErrorCode.PAYMENT_NOT_FOUND,
            },
        )
    return payment


@router.post("/{payment_id}/confirm")
async def confirm_payment(
    payment_id: int,
    tx_hash: str,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(
            status_code=404,
            detail={
                "success": False,
                "error": ErrorCode.PAYMENT_NOT_FOUND.value,
                "message": "Payment not found",
                "code": ErrorCode.PAYMENT_NOT_FOUND,
            },
        )
    if payment.from_address != user["address"]:
        raise HTTPException(
            status_code=403,
            detail={
                "success": False,
                "error": ErrorCode.UNAUTHORIZED.value,
                "message": "Only the payer can confirm this payment",
                "code": ErrorCode.UNAUTHORIZED,
            },
        )
    payment.status = "confirmed"
    payment.confirmed_at = datetime.utcnow()
    payment.tx_hash = tx_hash
    db.commit()
    return {
        "success": True,
        "data": {
            "id": payment.id,
            "status": payment.status,
            "tx_hash": payment.tx_hash,
        },
        "timestamp": datetime.utcnow().isoformat(),
    }
