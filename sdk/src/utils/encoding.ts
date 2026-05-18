/**
 * encoding.ts - ABI encoding utilities with BigInt support
 * Contributor: BossChaos (hermes-agent)
 * Fixes: #52, #54 - BigInt overflow, hex prefix validation
 */

const MAX_UINT256 = 2n ** 256n - 1n;

/**
 * FIX #52: Proper BigInt bounds checking and hex prefix handling
 */
export function hexToBigInt(hex: string): bigint {
  if (typeof hex !== "string") {
    throw new Error("Input must be a string");
  }
  if (!hex.startsWith("0x") && !hex.startsWith("0X")) {
    hex = "0x" + hex;
  }
  const value = BigInt(hex);
  // FIX: Bounds check for uint256
  if (value < 0n || value > MAX_UINT256) {
    throw new Error("Value out of uint256 range");
  }
  return value;
}

export function padTo32Bytes(hex: string): string {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length > 64) {
    throw new Error("Value exceeds 32 bytes");
  }
  return "0x" + clean.padStart(64, "0");
}

/**
 * FIX #54: Handle BigInt encoding with proper bounds
 */
export function encodeUint256(value: bigint | string): string {
  const val = typeof value === "string" ? hexToBigInt(value) : value;
  if (val < 0n) throw new Error("Negative value");
  if (val > MAX_UINT256) throw new Error("Overflow: exceeds uint256 max");
  return padTo32Bytes("0x" + val.toString(16));
}

export function decodeUint256(hex: string): bigint {
  return hexToBigInt(padTo32Bytes(hex));
}

export function encodeAddress(address: string): string {
  const clean = address.startsWith("0x") ? address.slice(2) : address;
  if (clean.length !== 40) {
    throw new Error("Invalid address length: expected 40 hex chars");
  }
  return padTo32Bytes("0x" + clean);
}
