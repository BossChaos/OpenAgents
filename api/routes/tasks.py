"""Task management endpoints for bounty assignments."""

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

from ..models.database import get_db, Task
from ..middleware.auth import get_current_user

router = APIRouter(prefix="/tasks", tags=["tasks"])

VALID_STATUSES = {"open", "assigned", "in_progress", "review", "completed", "cancelled"}

# FIX: WebSocket connection manager for real-time task updates
class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []
        self.task_subscriptions: dict[str, list[WebSocket]] = {}

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        for task_id in list(self.task_subscriptions.keys()):
            if websocket in self.task_subscriptions[task_id]:
                self.task_subscriptions[task_id].remove(websocket)

    def subscribe(self, websocket: WebSocket, task_id: str):
        if task_id not in self.task_subscriptions:
            self.task_subscriptions[task_id] = []
        self.task_subscriptions[task_id].append(websocket)

    async def broadcast_task_update(self, task_id: str, data: dict):
        for ws in self.task_subscriptions.get(task_id, []):
            try:
                await ws.send_json(data)
            except Exception:
                pass  # Connection may be dead

manager = ConnectionManager()


class TaskCreate(BaseModel):
    title: str
    description: str
    reward_amount: float
    agent_id: Optional[int] = None
    deadline: Optional[datetime] = None


class TaskStatusUpdate(BaseModel):
    status: str


@router.post("/")
async def create_task(task: TaskCreate, user=Depends(get_current_user), db=Depends(get_db)):
    new_task = Task(
        title=task.title,
        description=task.description,
        reward_amount=task.reward_amount,
        creator_id=user["id"],
        agent_id=task.agent_id,
        status="open",
        created_at=datetime.utcnow(),
        deadline=task.deadline,
    )
    db.add(new_task)
    db.commit()
    db.refresh(new_task)
    return {"id": new_task.id, "status": new_task.status}


@router.get("/")
async def list_tasks(
    status: Optional[str] = None,
    creator: Optional[str] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db=Depends(get_db),
):
    query = db.query(Task)
    if status:
        query = query.filter(Task.status == status)
    if creator:
        query = query.filter(Task.creator_id == creator)
    return query.order_by(Task.created_at.desc()).offset(skip).limit(limit).all()


@router.get("/{task_id}")
async def get_task(task_id: int, db=Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@router.patch("/{task_id}/status")
async def update_task_status(
    task_id: int,
    update: TaskStatusUpdate,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    # FIX: Validate status against allowed values
    if update.status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of: {', '.join(sorted(VALID_STATUSES))}")

    if task.creator_id != user["id"]:
        raise HTTPException(status_code=403, detail="Only the creator can update status")

    task.status = update.status
    task.updated_at = datetime.utcnow()
    db.commit()

    # FIX: Broadcast update to subscribed WebSocket clients
    await manager.broadcast_task_update(str(task_id), {
        "task_id": task_id,
        "status": task.status,
        "updated_at": task.updated_at.isoformat(),
    })

    return {"id": task.id, "status": task.status}


@router.delete("/{task_id}")
async def cancel_task(task_id: int, user=Depends(get_current_user), db=Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    if task.creator_id != user["id"]:
        raise HTTPException(status_code=403, detail="Only the creator can cancel")
    if task.status not in ("open", "assigned"):
        raise HTTPException(status_code=400, detail="Cannot cancel an active task")
    task.status = "cancelled"
    db.commit()
    return {"id": task.id, "status": "cancelled"}


# FIX: WebSocket endpoint for real-time task status updates
@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket, task_id: Optional[str] = None):
    await manager.connect(websocket)
    if task_id:
        manager.subscribe(websocket, task_id)
    try:
        while True:
            data = await websocket.receive_json()
            if data.get("action") == "subscribe" and data.get("task_id"):
                manager.subscribe(websocket, data["task_id"])
                await websocket.send_json({"status": "subscribed", "task_id": data["task_id"]})
            elif data.get("action") == "unsubscribe" and data.get("task_id"):
                pass  # unsubscribed on disconnect
    except WebSocketDisconnect:
        manager.disconnect(websocket)
