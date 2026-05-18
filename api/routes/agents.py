"""Agent discovery and reputation endpoints."""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

from ..models.database import get_db, Agent
from ..middleware.auth import get_current_user, require_role

router = APIRouter(prefix="/agents", tags=["agents"])


class AgentResponse(BaseModel):
    agent_id: str
    name: str
    owner: str
    endpoint: str
    reputation: int
    tasks_completed: int
    registered_at: datetime
    active: bool


class AgentCreate(BaseModel):
    agent_id: str
    name: str
    endpoint: str
    metadata: Optional[dict] = None


class AgentUpdate(BaseModel):
    name: Optional[str] = None
    endpoint: Optional[str] = None
    metadata: Optional[dict] = None


class ReputationUpdate(BaseModel):
    delta: int


@router.get("/", response_model=List[AgentResponse])
async def list_agents(
    active_only: bool = Query(True),
    min_reputation: int = Query(0),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db=Depends(get_db),
):
    # FIX: Filter out soft-deleted agents (active=0) by default
    query = db.query(Agent)
    if active_only:
        query = query.filter(Agent.active == 1)
    query = query.filter(Agent.reputation >= min_reputation)
    return query.order_by(Agent.reputation.desc()).offset(offset).limit(limit).all()


@router.get("/{agent_id}", response_model=AgentResponse)
async def get_agent(agent_id: str, db=Depends(get_db)):
    # FIX: Return 404 for soft-deleted agents instead of exposing them
    agent = db.query(Agent).filter(
        Agent.agent_id == agent_id,
        Agent.active == 1
    ).first()
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")
    return agent


@router.post("/")
async def register_agent(
    agent: AgentCreate,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    existing = db.query(Agent).filter(Agent.agent_id == agent.agent_id).first()
    if existing:
        if existing.active == 0:
            # FIX: Allow re-registration of a soft-deleted agent
            existing.active = 1
            existing.name = agent.name
            existing.endpoint = agent.endpoint
            db.commit()
            db.refresh(existing)
            return {"id": existing.id, "status": "reactivated"}
        raise HTTPException(status_code=409, detail="Agent already exists")

    new_agent = Agent(
        agent_id=agent.agent_id,
        name=agent.name,
        owner=user["id"],
        endpoint=agent.endpoint,
        reputation=0,
        tasks_completed=0,
        registered_at=datetime.utcnow(),
        active=1,
    )
    db.add(new_agent)
    db.commit()
    db.refresh(new_agent)
    return {"id": new_agent.id, "status": "registered"}


@router.patch("/{agent_id}")
async def update_agent(
    agent_id: str,
    update: AgentUpdate,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    agent = db.query(Agent).filter(
        Agent.agent_id == agent_id,
        Agent.owner == user["id"]
    ).first()
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    if update.name is not None:
        agent.name = update.name
    if update.endpoint is not None:
        agent.endpoint = update.endpoint
    if update.metadata is not None:
        agent.metadata = update.metadata

    db.commit()
    db.refresh(agent)
    return {"id": agent.id, "status": "updated"}


@router.post("/{agent_id}/deactivate")
async def deactivate_agent(
    agent_id: str,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    agent = db.query(Agent).filter(
        Agent.agent_id == agent_id,
        Agent.owner == user["id"]
    ).first()
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")
    agent.active = 0
    db.commit()
    return {"id": agent.id, "status": "deactivated"}


@router.post("/{agent_id}/reputation")
async def update_reputation(
    agent_id: str,
    update: ReputationUpdate,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    agent = db.query(Agent).filter(Agent.agent_id == agent_id).first()
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")
    agent.reputation = max(0, agent.reputation + update.delta)
    db.commit()
    db.refresh(agent)
    return {"id": agent.id, "reputation": agent.reputation}
