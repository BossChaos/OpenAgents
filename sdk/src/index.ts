import { RpcProvider } from "./providers/rpc";
import { Wallet } from "./auth/wallet";
import { SessionManager } from "./auth/session";

export interface OpenAgentsConfig {
  rpcUrl: string;
  chainId: number;
  apiBaseUrl: string;
}

export class OpenAgentsSDK {
  private provider: RpcProvider;
  private wallet: Wallet | null = null;
  private session: SessionManager | null = null;
  private apiBaseUrl: string;

  constructor(config: OpenAgentsConfig) {
    this.provider = new RpcProvider({
      url: config.rpcUrl,
      chainId: config.chainId,
    });
    this.apiBaseUrl = config.apiBaseUrl;
  }

  /**
   * Initialize wallet and session for a given private key.
   */
  async init(privateKey: string): Promise<void> {
    this.wallet = new Wallet({
      privateKey,
      provider: this.provider,
    });
    this.session = new SessionManager({
      wallet: this.wallet,
      apiBaseUrl: this.apiBaseUrl,
    });
  }

  /**
   * Get the current wallet address.
   */
  get address(): string | undefined {
    return this.wallet?.address;
  }

  /**
   * Get the RPC provider.
   */
  getProvider(): RpcProvider {
    return this.provider;
  }

  /**
   * Get session token for API calls.
   */
  async getSessionToken(): Promise<string> {
    if (!this.session) throw new Error("SDK not initialized");
    return this.session.getToken();
  }

  /**
   * FIX: Estimate gas for a transaction with a safety margin.
   * Prevents out-of-gas errors by adding 20% buffer.
   */
  async estimateGas(tx: { to: string; data: string; value?: bigint }): Promise<bigint> {
    if (!this.wallet) throw new Error("Wallet not initialized");

    const gasEstimate = await this.provider.call("eth_estimateGas", [
      {
        from: this.wallet.address,
        to: tx.to,
        data: tx.data,
        value: tx.value ? `0x${tx.value.toString(16)}` : "0x0",
      },
    ]) as string;

    const gas = BigInt(gasEstimate);
    // FIX: Add 20% safety margin to prevent out-of-gas reverts
    return (gas * 120n) / 100n;
  }

  /**
   * FIX: Send a transaction with automatic gas estimation and chainId validation.
   */
  async sendTransaction(tx: { to: string; data: string; value?: bigint }): Promise<string> {
    if (!this.wallet) throw new Error("Wallet not initialized");

    const gasLimit = await this.estimateGas(tx);
    const chainId = this.provider.getChainId();

    return this.wallet.sendTransaction({
      to: tx.to,
      data: tx.data,
      value: tx.value ?? 0n,
      gasLimit,
      chainId,
    });
  }

  /**
   * Fetch available tasks from the API.
   */
  async getOpenTasks(): Promise<any[]> {
    const token = await this.getSessionToken();
    const res = await fetch(`${this.apiBaseUrl}/tasks`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error(`API error: ${res.status}`);
    return res.json();
  }

  /**
   * Get tasks assigned to the current wallet.
   */
  async getMyTasks(): Promise<any[]> {
    const token = await this.getSessionToken();
    const res = await fetch(`${this.apiBaseUrl}/tasks?creator=${this.address}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error(`API error: ${res.status}`);
    return res.json();
  }

  /**
   * Logout and clear session.
   */
  logout(): void {
    this.session?.logout();
  }
}
