"""Agent management endpoints."""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator
from typing import Optional, List
from datetime import datetime
from urllib.parse import urlparse
import re

from ..models.database import get_db, Agent
from ..middleware.auth import get_current_user

router = APIRouter(prefix="/agents", tags=["agents"])

VALID_STATUSES = {"active", "paused", "retired"}

# FIX #173: Strict URL validation
URL_PATTERN = re.compile(r'^https?://[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+(/[^\s]*)?$')

class AgentCreate(BaseModel):
    name: str
    description: str
    metadata_url: Optional[str] = None
    owner_address: Optional[str] = None

    @field_validator('metadata_url')
    @classmethod
    def validate_url(cls, v):
        if v is None:
            return v
        # FIX: Reject non-HTTP URLs and potential SSRF
        if not URL_PATTERN.match(v):
            raise ValueError("Invalid URL format")
        parsed = urlparse(v)
        # FIX: Block localhost, internal IPs, and data: URLs
        if parsed.hostname in ('localhost', '127.0.0.1', '0.0.0.0'):
            raise ValueError("Internal URLs not allowed")
        return v

class AgentResponse(BaseModel):
    id: int
    name: str
    description: str
    metadata_url: Optional[str]
    status: str
    created_at: datetime

@router.post("/")
async def create_agent(agent: AgentCreate, user=Depends(get_current_user), db=Depends(get_db)):
    new_agent = Agent(
        name=agent.name,
        description=agent.description,
        metadata_url=agent.metadata_url,
        owner_address=agent.owner_address or user.get("address"),
        status="active",
        created_at=datetime.utcnow(),
    )
    db.add(new_agent)
    db.commit()
    db.refresh(new_agent)
    return {"id": new_agent.id, "status": new_agent.status}

@router.get("/")
async def list_agents(
    status: Optional[str] = None,
    owner: Optional[str] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    db=Depends(get_db),
):
    query = db.query(Agent).filter(Agent.status != "deleted")
    if status:
        query = query.filter(Agent.status == status)
    if owner:
        query = query.filter(Agent.owner_address == owner)
    return query.order_by(Agent.created_at.desc()).offset(skip).limit(limit).all()

@router.get("/{agent_id}")
async def get_agent(agent_id: int, db=Depends(get_db)):
    agent = db.query(Agent).filter(
        Agent.id == agent_id,
        Agent.status != "deleted"
    ).first()
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")
    return agent

@router.delete("/{agent_id}")
async def delete_agent(agent_id: int, user=Depends(get_current_user), db=Depends(get_db)):
    agent = db.query(Agent).filter(Agent.id == agent_id).first()
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")
    if agent.owner_address != user["address"]:
        raise HTTPException(status_code=403, detail="Not owner")
    agent.status = "deleted"
    db.commit()
    return {"id": agent.id, "status": "deleted"}
