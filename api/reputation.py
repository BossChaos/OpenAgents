"""reputation.py - Agent reputation scoring system"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from collections import defaultdict
from datetime import datetime

router = APIRouter(prefix="/reputation", tags=["reputation"])

class ReputationScore(BaseModel):
    agent_id: str
    score: float
    total_tasks: int
    successful_tasks: int
    avg_rating: float
    last_updated: str

# In-memory reputation store (production should use persistent DB)
_store: dict[str, dict] = defaultdict(lambda: {
    "score": 1000.0,
    "total_tasks": 0,
    "successful_tasks": 0,
    "ratings": [],
    "last_updated": datetime.utcnow().isoformat()
})

@router.get("/{agent_id}", response_model=ReputationScore)
async def get_reputation(agent_id: str):
    """Get agent reputation score"""
    data = _store[agent_id]
    ratings = data["ratings"]
    return ReputationScore(
        agent_id=agent_id,
        score=data["score"],
        total_tasks=data["total_tasks"],
        successful_tasks=data["successful_tasks"],
        avg_rating=sum(ratings)/len(ratings) if ratings else 0.0,
        last_updated=data["last_updated"]
    )

@router.post("/{agent_id}/rate")
async def rate_agent(agent_id: str, successful: bool, rating: float = 5.0):
    """Rate agent performance after task completion"""
    rating = max(1.0, min(5.0, rating))  # Clamp 1-5
    data = _store[agent_id]
    data["total_tasks"] += 1
    data["ratings"].append(rating)
    if successful:
        data["successful_tasks"] += 1
    # ELO-style score update
    k = 32
    expected = 1 / (1 + 10**((1500 - data["score"]) / 400))
    data["score"] += k * (rating/5.0 - expected)
    data["last_updated"] = datetime.utcnow().isoformat()
    return {"new_score": round(data["score"], 2)}

@router.get("/leaderboard")
async def leaderboard(limit: int = 20):
    """Get top agents by reputation"""
    sorted_agents = sorted(_store.items(), key=lambda x: -x[1]["score"])
    return [
        {"agent_id": aid, "score": round(d["score"], 2), "tasks": d["total_tasks"]}
        for aid, d in sorted_agents[:limit]
    ]
