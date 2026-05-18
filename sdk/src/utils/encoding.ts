/**
 * ABI encoding/decoding utilities for EVM-compatible contract interactions.
 */

export type AbiType = "uint256" | "address" | "bytes32" | "string" | "bool" | "uint128" | "int256";

export interface AbiParam {
  type: AbiType;
  value: string | number | bigint | boolean;
}

const MAX_UINT256 = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

export function encodeUint256(value: bigint | number): string {
  const n = BigInt(value);
  if (n < 0n || n > MAX_UINT256) {
    throw new Error(`encodeUint256: value ${n} out of uint256 range`);
  }
  return n.toString(16).padStart(64, "0");
}

export function encodeAddress(address: string): string {
  if (!/^0x[0-9a-fA-F]{40}$/.test(address)) {
    throw new Error(`encodeAddress: invalid address ${address}`);
  }
  const cleaned = address.startsWith("0x") ? address.slice(2) : address;
  return cleaned.toLowerCase().padStart(64, "0");
}

export function encodeBytes32(data: string): string {
  const cleaned = data.startsWith("0x") ? data.slice(2) : data;
  if (cleaned.length > 64) {
    throw new Error("encodeBytes32: data exceeds 32 bytes");
  }
  return cleaned.padEnd(64, "0");
}

export function encodeBool(value: boolean): string {
  return value ? "1".padStart(64, "0") : "0".padStart(64, "0");
}

export function encodeParams(params: AbiParam[]): string {
  let encoded = "0x";
  for (const param of params) {
    switch (param.type) {
      case "uint256":
      case "uint128":
        encoded += encodeUint256(BigInt(param.value as number));
        break;
      case "int256":
        {
          const n = BigInt(param.value as number);
          if (n < 0n) {
            const absVal = (-n - 1n) ^ MAX_UINT256;
            encoded += (absVal + 1n).toString(16).padStart(64, "0");
          } else {
            encoded += n.toString(16).padStart(64, "0");
          }
        }
        break;
      case "address":
        encoded += encodeAddress(param.value as string);
        break;
      case "bytes32":
        encoded += encodeBytes32(param.value as string);
        break;
      case "bool":
        encoded += encodeBool(param.value as boolean);
        break;
      case "string":
        {
          const hexStr = Buffer.from(param.value as string, "utf8").toString("hex");
          const paddedLen = Math.ceil(hexStr.length / 2);
          encoded += (paddedLen).toString(16).padStart(64, "0");
          encoded += hexStr.padEnd(((paddedLen + 31) >> 5) * 64, "0");
        }
        break;
    }
  }
  return encoded;
}

export function decodeHex(hex: string): bigint {
  if (!hex.startsWith("0x")) {
    throw new Error(`decodeHex: missing 0x prefix in "${hex}"`);
  }
  const cleaned = hex.slice(2);
  if (!/^[0-9a-fA-F]+$/.test(cleaned)) {
    throw new Error(`decodeHex: invalid hex characters in "${hex}"`);
  }
  return BigInt(hex);
}

export function decodeUint256(slot: string): bigint {
  const cleaned = slot.startsWith("0x") ? slot.slice(2) : slot;
  const padded = cleaned.padStart(64, "0");
  return BigInt("0x" + padded);
}

export function decodeAddress(slot: string): string {
  const raw = slot.slice(-40).padStart(40, "0");
  return "0x" + raw.toLowerCase();
}

export function decodeBool(slot: string): boolean {
  return BigInt("0x" + slot) !== 0n;
}

export function functionSelector(signature: string): string {
  const { createHash } = require("crypto");
  const hash = createHash("sha3-keccak-256").update(signature).digest("hex");
  return "0x" + hash.slice(0, 8);
}

export function packCalldata(selector: string, params: AbiParam[]): string {
  const encodedParams = encodeParams(params).slice(2);
  return selector + encodedParams;
}
