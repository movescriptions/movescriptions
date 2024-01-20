import { MintPayload } from "../types"
import { arrayify, hexlify, type BytesLike } from "@ethersproject/bytes"
import { keccak256 } from "@ethersproject/keccak256"
import { gpu_init, nonce_search } from './nonce-search';
import { pow, matchDifficulty } from "../../utils/pow"

/* eslint-disable @typescript-eslint/no-explicit-any */
const ctx: Worker = self as any;
/* eslint-enable @typescript-eslint/no-explicit-any */

let isMine = true;

ctx.onmessage = async (event: MessageEvent<any>) => {
  const { type, payload } = event.data;
  console.log('[CPU Miner]: worker handle message:', type, 'payload:', payload);

  try {
    switch (type) {
      case 'mint':
        isMine = true;
        await searchNonce(payload);
        break;
      case 'stop':
        isMine = false;
        break;
      default:
        console.warn(`Unknown message type: ${type}`);
    }
  } catch (e: any) {
    console.log('[CPU Miner]: worker handle message error:', e);
  }
}

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function notifyProgress(id: string, hashRate: number) {
  ctx.postMessage({
    type: 'progress',
    payload: {
      id: id,
      hashRate: hashRate,
    }
  });
}

async function notifyEnd(id: string, nonce: number | undefined, hash: string | undefined) {
  ctx.postMessage({
    type: 'end',
    payload: {
      id: id,
      nonce: nonce,
      hash: hash,
    }
  });
}

async function notifyError(e: Error) {
  ctx.postMessage({
    type: 'error',
    payload: {
      error: e,
      reason: 'init gpu fail'
    }
  });
}

export const hash = (data: BytesLike): Uint8Array =>{
  return arrayify(keccak256(data))
}

export function concatBytes(array: Uint8Array, u32: number): Uint8Array {
  const buffer = new ArrayBuffer(4); // 4 bytes for 32bit number
  const view = new DataView(buffer);
  view.setUint32(0, u32, true); // true for little-endian

  const byteArray = new Uint8Array(buffer);

  const result = new Uint8Array(array.length + byteArray.length);
  result.set(array);
  result.set(byteArray, array.length);
  return result;
}

export const makeKeyPrefix = (powData: Uint8Array, nonceHigh: number): Uint8Array=>{
  return concatBytes(hash(powData), nonceHigh)
}

function getHigh32Bits(num: number): number {
  return Math.floor(num / Math.pow(2, 32));
}

function concatNonce(high: number, low: number): number {
  return (high * Math.pow(2, 32)) + (low >>> 0);
}

const searchNonce = async (payload: MintPayload) => {
  const { id, powData, difficulty, seqStart, seqEnd } = payload;
  let lastTime = new Date().getTime();
  let nonce = seqStart

  console.log("inputData:", hexlify(powData))

  try {
    console.log(`[Miner]: gpu init...`);
    await gpu_init();
  } catch (e) {
    notifyError(e)
    return;
  }

  while(isMine && nonce < seqEnd) {
    const nonceHigh = getHigh32Bits(nonce);
    const keyPrefixBytes = makeKeyPrefix(powData, nonceHigh);
    const nonceLows = await nonce_search(keyPrefixBytes, difficulty);

    if (nonceLows && nonceLows.length > 0) {
      console.log(
        `[Miner]: found ${nonceLows.length} nonce:${nonceLows}, match difficulty: ${difficulty}`
      );

      for (let i = 0; i < nonceLows.length; i++) {
        const nonce = concatNonce(nonceHigh, nonceLows[i]);

        const data = pow(powData, nonce)
        if (matchDifficulty(data, difficulty)) {
          notifyEnd(id, nonce, hexlify(data))
          return
        }
      }

      break;
    }

    if (nonce % 10000 == 0) {
      const now = new Date().getTime();
      const hashRate = Math.floor(10000 / ((now - lastTime) / 1000));
      lastTime = now;

      notifyProgress(id, hashRate)
      await sleep(0)
    }

    nonce = concatNonce(nonceHigh + 1, 0)
  }

  notifyEnd(id, undefined, undefined)
}
