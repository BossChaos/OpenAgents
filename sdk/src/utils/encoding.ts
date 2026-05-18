/**
 * encoding.ts - ABI encoding utilities for EVM contracts
 * Contributor: BossChaos (hermes-agent) | Environment: Linux x86_64
 * Fixes: #47, #52, #54 - uint256 bounds, hex prefix, padding
 */

const MAX_UINT256 = 2n ** 256n - 1n;

/**
 * Convert a hex string to bigint with validation
 * FIX #47: Validate 0x prefix and uint256 bounds
 */
export function hexToBigInt(hex: string): bigint {
  if (!hex.startsWith("0x") && !hex.startsWith("0X")) {
    hex = "0x" + hex;
  }
  const value = BigInt(hex);
  // FIX: Bounds check
  if (value < 0n || value > MAX_UINT256) {
    throw new Error("Value out of uint256 range");
  }
  return value;
}

/**
 * Pad a hex string to 32 bytes
 * FIX #52: Proper padding validation
 */
export function padTo32Bytes(hex: string): string {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length > 64) {
    throw new Error("Value exceeds 32 bytes");
  }
  return "0x" + clean.padStart(64, "0");
}

/**
 * Encode a uint256 value as a 32-byte hex string
 * FIX #54: Add input validation
 */
export function encodeUint256(value: bigint | string): string {
  const val = typeof value === "string" ? hexToBigInt(value) : value;
  if (val < 0n) throw new Error("Negative value");
  if (val > MAX_UINT256) throw new Error("Overflow: exceeds uint256 max");
  return padTo32Bytes("0x" + val.toString(16));
}

/**
 * Decode a 32-byte hex string to bigint
 */
export function decodeUint256(hex: string): bigint {
  const padded = padTo32Bytes(hex);
  return hexToBigInt(padded);
}

/**
 * Encode a string to bytes32
 */
export function encodeString(str: string): string {
  const hex = Buffer.from(str).toString("hex");
  if (hex.length > 64) throw new Error("String too long for bytes32");
  return padTo32Bytes("0x" + hex);
}

/**
 * Encode an address (20 bytes) to 32 bytes
 */
export function encodeAddress(address: string): string {
  const clean = address.startsWith("0x") ? address.slice(2) : address;
  if (clean.length !== 40) {
    throw new Error("Invalid address length: expected 40 hex chars");
  }
  return padTo32Bytes("0x" + clean);
}
