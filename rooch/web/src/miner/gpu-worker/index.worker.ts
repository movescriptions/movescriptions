'use client';
self.window = self;

import Long from "long"
import { MintPayload } from "../types"
import { arrayify, hexlify, type BytesLike } from "@ethersproject/bytes"

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

async function notifyProgress(id: string, nonce: number, hash: string, hashRate: number) {
  ctx.postMessage({
    type: 'progress',
    payload: {
      id: id,
      nonce: nonce,
      hash: hash,
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

export function concatArrayAndNonce(array: Uint8Array, nonceHigh32: number, nonceLow32: number): Uint8Array {
  const highBuffer = new ArrayBuffer(4);  
  const highView = new DataView(highBuffer);
  highView.setUint32(0, nonceHigh32, true);
  const highByteArray = new Uint8Array(highBuffer);

  const lowBuffer = new ArrayBuffer(4);  
  const lowView = new DataView(lowBuffer);
  lowView.setUint32(0, nonceLow32, true);
  const lowByteArray = new Uint8Array(lowBuffer);
 
  const result = new Uint8Array(array.length + highByteArray.length + lowByteArray.length);
  result.set(array);
  result.set(lowByteArray, array.length);
  result.set(highByteArray, array.length + lowByteArray.length);
  return result;
}

function getHigh32Bits(num: number): number {
  return Math.floor(num / Math.pow(2, 32));
}

function concatNonce(high: number, low: number): number {
  return (high * Math.pow(2, 32)) + low;
}

const searchNonce = async (payload: MintPayload) => {
  const { keccak256 } = await import("@ethersproject/keccak256")
  const { pow, matchDifficulty } = await import("../../utils/pow")
  const { gpu_init, nonce_search } = await import('./nonce-search')

  const hash = (data: BytesLike): Uint8Array =>{
    return arrayify(keccak256(data))
  }

  const makeKey = (powData: Uint8Array, nonceHigh: number): Uint8Array=>{
    return concatArrayAndNonce(hash(powData), nonceHigh, 0)
  }

  const { id, powData, difficulty, seqStart, seqEnd } = payload;
  let lastTime = new Date().getTime();
  let nonce = seqStart

  console.log("inputData:", hexlify(powData))

  try {
    console.log(`[Miner]: gpu init...`);
    await gpu_init();
  } catch (e: any) {
    notifyError(e)
    return;
  }

  let count = 0;
  
  while(isMine && nonce < seqEnd) {
    if (nonce % 2 == 0) {
      const now = new Date().getTime();
      const hashRate = Math.floor(count / ((now - lastTime) / 1000));
      lastTime = now;
      count = 0;

      const data = pow(powData, nonce)
      notifyProgress(id, nonce, hexlify(data), hashRate)
      await sleep(0)
    }

    const nonceHigh = getHigh32Bits(nonce);
    const keyBytes = makeKey(powData, nonceHigh);
    const result = await nonce_search(keyBytes, difficulty);
    const nonceLows = result.result;
    count = count + result.calcCount;
    
    if (nonceLows && nonceLows.length > 0) {
      console.log(
        `[Miner]: found ${nonceLows.length} high nonce:${nonceHigh}, low nonces:${nonceLows}, match difficulty: ${difficulty}`
      );

      for (let i = 0; i < nonceLows.length; i++) {
        const nonce = concatNonce(nonceHigh, nonceLows[i]);

        const data = pow(powData, nonce)

        const longVal = Long.fromNumber(nonce, true);
        const byteArray = new Uint8Array(longVal.toBytesLE());

        console.log(
          `[Miner]: nonce:${nonce}, nonceHex:${hexlify(byteArray)}, hash: ${hexlify(data)}`
        );

        if (matchDifficulty(data, difficulty)) {
          notifyEnd(id, nonce, hexlify(data))
          return
        }
      }

      break;
    }
    
    nonce = concatNonce(nonceHigh + 1, 0)
  }

  notifyEnd(id, undefined, undefined)

  console.log(`[Miner]: stoped`);
}
