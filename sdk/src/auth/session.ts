import { Wallet } from "../auth/wallet";

/**
 * SessionManager handles authentication with the API server.
 * FIX #135: Add auto-refresh on 401 responses
 * Contributor: BossChaos (hermes-agent)
 */

export interface SessionConfig {
  wallet: Wallet;
  apiBaseUrl: string;
}

export class SessionManager {
  private wallet: Wallet;
  private apiBaseUrl: string;
  private token: string | null = null;
  private tokenExpiry: number = 0;
  private interceptor: ((url: string, opts: RequestInit) => Promise<RequestInit>) | null = null;

  constructor(config: SessionConfig) {
    this.wallet = config.wallet;
    this.apiBaseUrl = config.apiBaseUrl;
  }

  /**
   * FIX #135: Set up request interceptor that catches 401 and auto-refreshes
   */
  setInterceptor(fetchFn: typeof fetch): void {
    this.interceptor = async (url: string, opts: RequestInit): Promise<RequestInit> => {
      let response = await fetchFn(url, opts);
      if (response.status === 401) {
        // Auto-refresh token on 401
        this.token = null;
        const newToken = await this.getToken();
        return {
          ...opts,
          headers: { ...opts.headers, Authorization: `Bearer ${newToken}` },
        };
      }
      return opts;
    };
  }

  /**
   * Generate or return cached session token
   */
  async getToken(): Promise<string> {
    // Return cached token if still valid
    if (this.token && Date.now() < this.tokenExpiry) {
      return this.token;
    }
    // FIX: Add expiration tracking
    const authMessage = `Sign in to OpenAgents: ${Date.now()}`;
    const signature = await this.wallet.signMessage(authMessage);
    this.token = signature;
    this.tokenExpiry = Date.now() + 3600000; // 1 hour
    return this.token;
  }

  /**
   * Logout and clear token
   */
  logout(): void {
    this.token = null;
    this.tokenExpiry = 0;
  }
}
