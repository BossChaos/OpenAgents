/**
 * tasks.ts - Task query with pagination
 * Contributor: BossChaos (hermes-agent)
 * Fixes: #113 - getOpenTasks iteration
 */

export interface Task {
  id: number;
  title: string;
  status: string;
  reward: bigint;
}

export class TaskClient {
  private apiBase: string;

  constructor(apiBase: string) {
    this.apiBase = apiBase;
  }

  /**
   * FIX #113: Proper pagination for task listing
   */
  async *getOpenTasks(pageSize: number = 50): AsyncGenerator<Task> {
    let page = 1;
    let hasMore = true;

    while (hasMore) {
      const url = `${this.apiBase}/tasks?status=open&page=${page}&limit=${pageSize}`;
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      const tasks: Task[] = data.tasks || [];
      hasMore = data.hasNextPage || tasks.length >= pageSize;

      for (const task of tasks) {
        yield {
          id: task.id,
          title: task.title,
          status: task.status,
          reward: BigInt(task.reward),
        };
      }
      page++;
    }
  }

  async getAllOpenTasks(): Promise<Task[]> {
    const all: Task[] = [];
    for await (const task of this.getOpenTasks()) {
      all.push(task);
    }
    return all;
  }
}
