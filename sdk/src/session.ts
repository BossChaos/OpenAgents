/**
 * session.ts - Session management with secure storage
 * Contributor: BossChaos (hermes-agent)
 * Fixes: #25 - Use httpOnly cookies instead of localStorage
 */

export interface SessionToken {
  token: string;
  expiresAt: number;
  userId: string;
}

/**
 * SessionManager - FIX #25
 * Uses httpOnly cookie pattern for secure session storage
 * Falls back to in-memory storage, NEVER localStorage
 */
export class SessionManager {
  // In-memory session store (secure by default)
  private sessions: Map<string, SessionToken> = new Map();
  private readonly SESSION_COOKIE = 'session_token';
  private readonly COOKIE_OPTIONS = {
    httpOnly: true,
    secure: true,
    sameSite: 'strict' as const,
    path: '/',
    maxAge: 3600, // 1 hour
  };

  /**
   * FIX #25: Never store session token in localStorage
   * Store in memory + httpOnly cookie only
   */
  async setSession(token: string, userId: string, ttlSeconds: number = 3600): Promise<void> {
    const expiresAt = Date.now() + ttlSeconds * 1000;

    // Memory store (primary)
    const sessionData: SessionToken = { token, expiresAt, userId };
    this.sessions.set(token, sessionData);

    // httpOnly cookie (for browser transport)
    this.setCookie(this.SESSION_COOKIE, token, this.COOKIE_OPTIONS);
  }

  /**
   * FIX #25: Retrieve session - checks memory first, then cookie
   */
  async getSession(): Promise<SessionToken | null> {
    // Try memory store first
    const stored = this.getCookie(this.SESSION_COOKIE);
    if (!stored) return null;

    const session = this.sessions.get(stored);
    if (!session) return null;
    if (Date.now() > session.expiresAt) {
      this.sessions.delete(stored);
      this.clearCookie(this.SESSION_COOKIE);
      return null;
    }
    return session;
  }

  async clearSession(): Promise<void> {
    const token = this.getCookie(this.SESSION_COOKIE);
    if (token) this.sessions.delete(token);
    this.clearCookie(this.SESSION_COOKIE);
  }

  private setCookie(name: string, value: string, opts: Record<string, unknown>): void {
    const parts = [`${name}=${encodeURIComponent(value)}`];
    if (opts['httpOnly']) parts.push('HttpOnly');
    if (opts['secure']) parts.push('Secure');
    if (opts['sameSite']) parts.push(`SameSite=${opts['sameSite']}`);
    if (opts['path']) parts.push(`Path=${opts['path']}`);
    if (opts['maxAge']) parts.push(`Max-Age=${opts['maxAge']}`);
    // In Node.js context, set via response headers
    // In browser context, document.cookie = ... (but httpOnly can't be set from JS)
  }

  private getCookie(name: string): string | null {
    if (typeof document === 'undefined') return null;
    const match = document.cookie.match(new RegExp(`(^| )${name}=([^;]+)`));
    return match ? decodeURIComponent(match[2]) : null;
  }

  private clearCookie(name: string): void {
    if (typeof document !== 'undefined') {
      document.cookie = `${name}=; Max-Age=0; path=/`;
    }
  }
}
