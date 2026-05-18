/**
 * nonce.ts - Secure nonce generation
 * Contributor: BossChaos (hermes-agent)
 * Fixes: #67 - Replace Math.random with crypto
 */

import { randomBytes } from "crypto";

/**
 * FIX #67: Use crypto.randomBytes instead of Math.random
 */
export function generateNonce(length: number = 32): string {
  const bytes = randomBytes(length);
  return bytes.toString("hex");
}

/**
 * Generate a unique request ID
 */
export function generateRequestId(): string {
  const timestamp = Date.now().toString(36);
  const random = generateNonce(8);
  return `${timestamp}-${random}`;
}
