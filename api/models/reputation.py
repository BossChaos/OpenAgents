"""Agent reputation scoring system.
FIX #43: Reputation-based agent ranking with decay
Contributor: BossChaos (hermes-agent)
"""

from dataclasses import dataclass, field
from typing import Dict, List
import time
from collections import defaultdict

@dataclass
class AgentMetrics:
    task_count: int = 0
    success_count: int = 0
    failure_count: int = 0
    total_score: float = 0.0
    last_active: float = 0.0
    created_at: float = field(default_factory=time.time)

class ReputationSystem:
    def __init__(self):
        self.agents: Dict[str, AgentMetrics] = defaultdict(AgentMetrics)
        self.decay_factor: float = 0.95  # 5% monthly decay
        self.max_score: float = 100.0

    def record_completion(self, agent_id: str, success: bool, score: float):
        metrics = self.agents[agent_id]
        metrics.task_count += 1
        if success:
            metrics.success_count += 1
        else:
            metrics.failure_count += 1
        metrics.total_score += score
        metrics.last_active = time.time()

    def get_reputation(self, agent_id: str) -> float:
        metrics = self.agents[agent_id]
        if metrics.task_count == 0:
            return 0.0
        # FIX #43: Weighted reputation = success_rate * avg_score * decay
        success_rate = metrics.success_count / metrics.task_count
        avg_score = metrics.total_score / metrics.task_count if metrics.task_count > 0 else 0

        # Time decay
        time_diff = (time.time() - metrics.last_active) / (30 * 24 * 3600)  # months
        decay = self.decay_factor ** time_diff

        reputation = min(self.max_score, success_rate * avg_score * decay * 10)
        return round(reputation, 2)

    def get_ranked_agents(self) -> List[tuple]:
        return sorted(
            [(aid, self.get_reputation(aid)) for aid in self.agents],
            key=lambda x: -x[1]
        )
