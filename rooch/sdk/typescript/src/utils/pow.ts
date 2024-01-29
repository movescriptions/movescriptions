import Long from "long"
import { arrayify as bytesArrayify, hexlify as bytesHexlify, type BytesLike as bytesBytesLike } from "@ethersproject/bytes"
import { keccak256 } from "@ethersproject/keccak256"

export const hash = (data: BytesLike): Uint8Array =>{
  return arrayify(keccak256(data))
}

export function concatBytes(array: Uint8Array, u64: number): Uint8Array {
  const longVal = Long.fromNumber(u64, true);
  const byteArray = new Uint8Array(longVal.toBytesLE());

  const result = new Uint8Array(array.length + byteArray.length);
  result.set(array);
  result.set(byteArray, array.length);
  return result;
}

export const matchDifficulty = (data: Uint8Array, difficulty: number):boolean => {
  for(let i = 0; i < difficulty; i++) {
    if(data[i] !== 0) {
      return false;
    }
  }

  return true;
}

export const pow = (powData: Uint8Array, nonce: number)=>{
  return hash(concatBytes(hash(powData), nonce))
}

export const hexlify = bytesHexlify;
export const arrayify = bytesArrayify;
export type BytesLike = bytesBytesLike;