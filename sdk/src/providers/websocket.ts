import { EventEmitter } from "events";

export interface WsProviderConfig {
  url: string;
  reconnectIntervalMs?: number;
  maxReconnectAttempts?: number;
}

interface PendingRequest {
  resolve: (value: unknown) => void;
  reject: (reason: Error) => void;
}

export class WebSocketProvider extends EventEmitter {
  private url: string;
  private ws: WebSocket | null = null;
  private requestId = 0;
  private pendingRequests = new Map<number, PendingRequest>();
  private subscriptions = new Map<string, (data: unknown) => void>();
  private reconnectInterval: number;
  private maxReconnectAttempts: number;
  private reconnectCount = 0;
  private isConnected = false;
  private heartbeatInterval: NodeJS.Timeout | null = null;

  constructor(config: WsProviderConfig) {
    super();
    this.url = config.url;
    this.reconnectInterval = config.reconnectIntervalMs ?? 3000;
    this.maxReconnectAttempts = config.maxReconnectAttempts ?? 10;
  }

  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.url);

      this.ws.onopen = () => {
        this.isConnected = true;
        this.reconnectCount = 0;
        // FIX: Start heartbeat/ping mechanism to detect stale connections
        this.startHeartbeat();
        this.emit("connected");
        resolve();
      };

      this.ws.onmessage = (event) => {
        const data = JSON.parse(event.data as string);
        if (data.id && this.pendingRequests.has(data.id)) {
          const pending = this.pendingRequests.get(data.id)!;
          this.pendingRequests.delete(data.id);
          data.error ? pending.reject(new Error(data.error.message)) : pending.resolve(data.result);
        } else if (data.method === "eth_subscription") {
          const subId = data.params?.subscription;
          this.subscriptions.get(subId)?.(data.params.result);
        } else if (data.result === "pong") {
          // Heartbeat response
        }
      };

      this.ws.onclose = () => {
        this.isConnected = false;
        // FIX: Stop heartbeat on disconnect
        this.stopHeartbeat();
        this.emit("disconnected");
        this.attemptReconnect();
      };

      this.ws.onerror = (err) => {
        if (!this.isConnected) reject(new Error("WebSocket connection failed"));
        this.emit("error", err);
      };
    });
  }

  private attemptReconnect(): void {
    if (this.reconnectCount >= this.maxReconnectAttempts) {
      this.emit("maxReconnectsReached");
      return;
    }
    this.reconnectCount++;
    setTimeout(() => {
      this.connect()
        .then(() => {
          // FIX: Resubscribe to all previous subscriptions after reconnect
          this.resubscribeAll();
        })
        .catch(() => this.attemptReconnect());
    }, this.reconnectInterval);
  }

  // FIX: Resubscribe to all active subscriptions after reconnection
  private async resubscribeAll(): Promise<void> {
    for (const [subId, callback] of this.subscriptions) {
      try {
        await this.send("eth_subscribe", [subId]);
      } catch (err) {
        this.emit("resubscribeError", { subscriptionId: subId, error: err });
      }
    }
  }

  // FIX: Heartbeat/ping mechanism to detect stale connections
  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatInterval = setInterval(() => {
      if (this.ws && this.isConnected) {
        try {
          this.ws.send(JSON.stringify({ jsonrpc: "2.0", id: ++this.requestId, method: "ping", params: [] }));
        } catch {
          this.ws?.close();
        }
      }
    }, 15000); // Every 15 seconds
  }

  private stopHeartbeat(): void {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }

  async send(method: string, params: unknown[] = []): Promise<unknown> {
    if (!this.ws || !this.isConnected) {
      throw new Error("WebSocket not connected");
    }
    const id = ++this.requestId;
    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });
      this.ws!.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
    });
  }

  async subscribe(
    event: string,
    callback: (data: unknown) => void
  ): Promise<string> {
    const subId = (await this.send("eth_subscribe", [event])) as string;
    this.subscriptions.set(subId, callback);
    return subId;
  }

  async unsubscribe(subscriptionId: string): Promise<boolean> {
    this.subscriptions.delete(subscriptionId);
    return (await this.send("eth_unsubscribe", [subscriptionId])) as boolean;
  }

  disconnect(): void {
    this.stopHeartbeat();
    this.ws?.close();
    this.ws = null;
    this.isConnected = false;
    this.pendingRequests.clear();
  }
}
