
import { Keccak256 } from "@hazae41/keccak256"

Keccak256.set(await Keccak256.fromMorax())

/* eslint-disable @typescript-eslint/no-explicit-any */
const ctx: Worker = self as any;
/* eslint-enable @typescript-eslint/no-explicit-any */

let isMine = true;

ctx.onmessage = async (event: MessageEvent<any>) => {
  const { type, payload } = event.data;
  console.log('[CPU Miner]: worker handle message:', type, 'payload:', payload);

  try {
    switch (type) {
      case 'start':
        isMine = true;
        await searchNonce(payload.powInput, payload.difficulty);
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

const searchNonce = async (powInput: Uint8Array, difficulty: number) => {
  let nonce = new Date().getTime()
  while(powInput) {
    const data = hash(appendU64ToUint8Array(hash(powInput), BigInt(nonce)))
    if (matchDifficulty(data, difficulty)) {
      return nonce
    }

    nonce++;
  }
}

const hash = (data: Uint8Array): Uint8Array=>{
  return Keccak256.get().tryHash(data).unwrap().copyAndDispose()
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
