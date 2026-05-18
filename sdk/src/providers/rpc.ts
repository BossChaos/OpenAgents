/**
 * rpc.ts - JSON-RPC provider with batch support
 * Contributor: BossChaos (hermes-agent) | Environment: Linux x86_64
 * Fixes: #161 - JSON-RPC batch handling
 */

import { withRetry } from "../utils/retry";
import { encodeUint256 } from "../utils/encoding";

export interface JsonRpcRequest {
  jsonrpc: "2.0";
  method: string;
  params: any[];
  id: number;
}

export interface JsonRpcResponse {
  jsonrpc: "2.0";
  result?: any;
  error?: { code: number; message: string; data?: any };
  id: number;
}

export class JsonRpcProvider {
  private url: string;
  private nextId = 1;

  constructor(url: string) {
    this.url = url;
  }

  /**
   * FIX #161: Match responses to requests by id, handle partial failures
   */
  async batch(requests: { method: string; params: any[] }[]): Promise<any[]> {
    const body: JsonRpcRequest[] = requests.map((req, i) => ({
      jsonrpc: "2.0",
      method: req.method,
      params: req.params,
      id: this.nextId + i,
    }));

    const response = await fetch(this.url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const data = await response.json();
    const responses: JsonRpcResponse[] = Array.isArray(data) ? data : [data];
    this.nextId += requests.length;

    // FIX: Match by id and handle partial failures
    const idMap = new Map<number, any>();
    for (const resp of responses) {
      if (resp.error) {
        idMap.set(resp.id, new Error(resp.error.message));
      } else {
        idMap.set(resp.id, resp.result);
      }
    }

    return requests.map((req, i) => {
      const id = this.nextId - requests.length + i;
      const result = idMap.get(id);
      if (result instanceof Error) throw result;
      return result;
    });
  }

  async call(method: string, params: any[] = []): Promise<any> {
    const results = await this.batch([{ method, params }]);
    return results[0];
  }
}
