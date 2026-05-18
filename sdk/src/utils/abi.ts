/**
 * abi.ts - ABI encoding with BigInt overflow protection
 * Contributor: BossChaos (hermes-agent)
 * Fixes: #54 - BigInt overflow in ABI encoding
 */

const MAX_UINT256 = 2n ** 256n - 1n;
const MIN_INT256 = -(2n ** 255n);
const MAX_INT256 = 2n ** 255n - 1n;

/**
 * FIX #54: Validate BigInt values before encoding
 */
export function encodeABI(method: string, params: (string | number | bigint | boolean)[]): string {
  // Method signature
  let encoded = "0x";

  // Encode each parameter
  for (const param of params) {
    if (typeof param === "bigint") {
      // FIX: Bounds check for uint256
      if (param < 0n) throw new Error("Negative value for uint256");
      if (param > MAX_UINT256) throw new Error("BigInt overflow: exceeds uint256 max");
      const hex = param.toString(16).padStart(64, "0");
      encoded += hex;
    } else if (typeof param === "string") {
      if (param.startsWith("0x")) {
        // Hex string - validate length
        const clean = param.slice(2);
        if (clean.length > 64) throw new Error("Value exceeds 256 bits");
        encoded += clean.padStart(64, "0");
      } else {
        // Treat as string data
        encoded += encodeBytes(param);
      }
    } else if (typeof param === "number") {
      if (param < 0 || !Number.isSafeInteger(param)) {
        throw new Error("Unsafe integer: use bigint instead");
      }
      const hex = BigInt(param).toString(16).padStart(64, "0");
      encoded += hex;
    } else if (typeof param === "boolean") {
      encoded += param ? "1".padStart(64, "0") : "0".padStart(64, "0");
    }
  }
  return encoded;
}

function encodeBytes(str: string): string {
  const hex = Buffer.from(str, "utf8").toString("hex");
  const len = hex.length / 2;
  return hex.padEnd(len * 2 + (64 - (len % 32 || 32)) * 2, "0");
}
