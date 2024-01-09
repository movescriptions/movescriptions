
import { arrayify, hexlify } from "@ethersproject/bytes";
import { keccak256 } from "@ethersproject/keccak256"
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

const searchNonce = async (payload: MintPayload) => {
  const { id, powData, difficulty, seqStart, seqEnd } = payload;
  let lastTime = new Date().getTime();
  let nonce = seqStart

  while(nonce < seqEnd) {
    const data = hash(appendU64ToUint8Array(hash(powData), BigInt(nonce)))
    if (matchDifficulty(data, difficulty)) {
      notifyEnd(id, nonce, hexlify(data))
      return
    }

    if (nonce % 10000 == 0) {
      const now = new Date().getTime();
      const hashRate = Math.floor(10000 / ((now - lastTime) / 1000));
      lastTime = now;

      notifyProgress(id, hashRate)
      await sleep(0)
    }

    nonce++;
  }

  notifyEnd(id, undefined, undefined)
}

const hash = (data: Uint8Array): Uint8Array =>{
  return arrayify(keccak256(data))
}

function appendU64ToUint8Array(array: Uint8Array, u64: bigint): Uint8Array {
  const tempArray = new Uint8Array(8);
  for (let i = 0; i < 8; i++) {
      tempArray[i] = Number((u64 & (BigInt(0xff) << BigInt(i * 8))) >> BigInt(i * 8));
  }
  const result = new Uint8Array(array.length + tempArray.length);
  result.set(array);
  result.set(tempArray, array.length);
  return result;
}

const matchDifficulty = (data: Uint8Array, difficulty: number):boolean => {
  for(let i = 0; i < difficulty; i++) {
    if(data[i] !== 0) {
      return false;
    }
  }

  return true;
}
