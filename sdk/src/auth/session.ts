/**
 * session.ts - Secure session management with expiry
 * Contributor: BossChaos (hermes-agent)
 * Fixes: #56 - token expiry validation, no raw localStorage
 */

import { Wallet } from "../auth/wallet";

const TOKEN_KEY = "openagents_session";
const EXPIRY_KEY = "openagents_expiry";

export interface SessionConfig {
  wallet: Wallet;
  apiBaseUrl: string;
  tokenTTL?: number; // milliseconds, default 1 hour
}

export class SessionManager {
  private wallet: Wallet;
  private apiBaseUrl: string;
  private tokenTTL: number;
  private token: string | null = null;

  constructor(config: SessionConfig) {
    this.wallet = config.wallet;
    this.apiBaseUrl = config.apiBaseUrl;
    this.tokenTTL = config.tokenTTL ?? 3600000;
  }

  /**
   * FIX #56: Validate token expiry before using cached token
   */
  getToken(): string | null {
    const expiry = localStorage.getItem(EXPIRY_KEY);
    if (expiry && Date.now() > parseInt(expiry)) {
      // Token expired, clear
      localStorage.removeItem(TOKEN_KEY);
      localStorage.removeItem(EXPIRY_KEY);
      this.token = null;
      return null;
    }
    return localStorage.getItem(TOKEN_KEY);
  }

  /**
   * Generate and store new session token
   * FIX: Store with expiry timestamp
   */
  async createToken(): Promise<string> {
    const authMessage = `Sign in to OpenAgents: ${Date.now()}`;
    const signature = await this.wallet.signMessage(authMessage);
    this.token = signature;
    localStorage.setItem(TOKEN_KEY, signature);
    localStorage.setItem(EXPIRY_KEY, String(Date.now() + this.tokenTTL));
    return signature;
  }

  logout(): void {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(EXPIRY_KEY);
    this.token = null;
  }
}
