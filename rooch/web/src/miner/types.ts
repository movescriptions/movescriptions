

export const MAX_SEQUENCE = 0xffffffff;

export enum Status {
  Init,
  Idle,
  Runing
}

export interface IMintResult {
  nonce: bigint
}

export interface IMinerTask {
  id: string;
  powData: Uint8Array;
  difficulty: number;
  timestamp: number;
  onEnd: (result: IMintResult)=>void;
  onError: (err: Error)=>void;
  onProgress: (msg: ProgressPayload)=>void;
}

export interface IWorkerTask {
  id: string;
  powData: Uint8Array;
  difficulty: number;
  seqStart: number,
  seqEnd: number,
  timestamp: number;
}

export type MessageType = "mint" | "progress"

export type MintPayload = IWorkerTask

export type ProgressPayload = {
  id: string,
  progress: string,
}

export type EndPayload = {
  id: string,
  nonce: number | undefined,
}