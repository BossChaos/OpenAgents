import { Wallet } from "./wallet";
import { keccak256 } from "../utils/crypto";

export interface SessionConfig {
  wallet: Wallet;
  apiBaseUrl: string;
  autoRefresh?: boolean;
}

export interface SessionToken {
  token: string;
  expiresAt: number; // unix timestamp in seconds
  refreshToken: string;
  walletAddress: string;
}

export class SessionManager {
  private wallet: Wallet;
  private apiBaseUrl: string;
  private autoRefresh: boolean;
  private currentToken: SessionToken | null = null;
  private refreshPromise: Promise<SessionToken> | null = null;

  constructor(config: SessionConfig) {
    this.wallet = config.wallet;
    this.apiBaseUrl = config.apiBaseUrl;
    this.autoRefresh = config.autoRefresh ?? true;
    this.loadStoredSession();
  }

  private loadStoredSession(): void {
    if (typeof window !== "undefined" && window.localStorage) {
      const stored = localStorage.getItem(`session_${this.wallet.address}`);
      if (stored) {
        this.currentToken = JSON.parse(stored);
        // FIX: Check expiry on load — discard expired tokens
        if (this.currentToken && this.currentToken.expiresAt <= Math.floor(Date.now() / 1000)) {
          this.currentToken = null;
          localStorage.removeItem(`session_${this.wallet.address}`);
        }
      }
    }
  }

  private persistSession(token: SessionToken): void {
    this.currentToken = token;
    if (typeof window !== "undefined" && window.localStorage) {
      localStorage.setItem(`session_${this.wallet.address}`, JSON.stringify(token));
    }
  }

  async authenticate(): Promise<SessionToken> {
    const timestamp = Math.floor(Date.now() / 1000);
    const message = `Sign in to OpenAgents: ${timestamp}`;
    const signature = await this.wallet.signMessage(message);

    const res = await fetch(`${this.apiBaseUrl}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        address: this.wallet.address,
        message,
        signature,
        timestamp,
      }),
    });

    if (!res.ok) throw new Error(`Auth failed: ${res.status}`);
    const token: SessionToken = await res.json();
    this.persistSession(token);
    return token;
  }

  async getToken(): Promise<string> {
    // FIX: Check expiry before returning cached token
    if (this.currentToken && this.currentToken.expiresAt > Math.floor(Date.now() / 1000)) {
      return this.currentToken.token;
    }
    // Token expired or missing — refresh or re-authenticate
    if (this.currentToken?.refreshToken && this.currentToken.expiresAt > 0) {
      try {
        return (await this.refresh()).token;
      } catch {
        // Refresh failed — fall through to re-authenticate
      }
    }
    const session = await this.authenticate();
    return session.token;
  }

  async refresh(): Promise<SessionToken> {
    // FIX: Prevent race condition with concurrent refresh callers
    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    if (!this.currentToken?.refreshToken) {
      return this.authenticate();
    }

    this.refreshPromise = (async () => {
      const res = await fetch(`${this.apiBaseUrl}/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refreshToken: this.currentToken!.refreshToken }),
      });

      if (!res.ok) {
        this.currentToken = null;
        return this.authenticate();
      }

      const token: SessionToken = await res.json();
      this.persistSession(token);
      return token;
    })();

    try {
      return await this.refreshPromise;
    } finally {
      this.refreshPromise = null;
    }
  }

  logout(): void {
    this.currentToken = null;
    if (typeof window !== "undefined" && window.localStorage) {
      localStorage.removeItem(`session_${this.wallet.address}`);
    }
  }

  isAuthenticated(): boolean {
    return this.currentToken !== null && this.currentToken.expiresAt > Math.floor(Date.now() / 1000);
  }
}
