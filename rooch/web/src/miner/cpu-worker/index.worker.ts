'use client';
self.window = self;
import { MintPayload } from "../types"

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

const searchNonce = async (payload: MintPayload) => {
  const { pow, matchDifficulty, hexlify } = await import("../../utils/pow")

  const { id, powData, difficulty, seqStart, seqEnd } = payload;
  let lastTime = new Date().getTime();
  let nonce = seqStart

  console.log("inputData:", hexlify(powData))
  while(nonce < seqEnd) {
    const data = pow(powData, nonce)
    if (matchDifficulty(data, difficulty)) {
      notifyEnd(id, nonce, hexlify(data))
      return
    }

    if (nonce % 10000 == 0) {
      const now = new Date().getTime();
      const hashRate = Math.floor(10000 / ((now - lastTime) / 1000));
      lastTime = now;

      notifyProgress(id, nonce, hexlify(data), hashRate)
      await sleep(0)
    }

    nonce++;
  }

  notifyEnd(id, undefined, undefined)
}

