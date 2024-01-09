

export const MAX_SEQUENCE = 0xffffffff;

export enum Status {
  Init,
  Idle,
  Runing
}

export interface IMintResult {
  nonce: number;
  hash: string;
}

export interface IMinerTask {
  id: string;
  powData: Uint8Array;
  difficulty: number;
  timestamp: number;
  onEnd: (result: IMintResult)=>void;
  onError: (err: Error)=>void;
  onProgress: (msg: string)=>void;
}

export interface IWorkerTask {
  id: string;
  powData: Uint8Array;
  difficulty: number;
  seqStart: number,
  seqEnd: number,
  timestamp: number;
}

export interface IWorkerStatus {
  hashRate: number;
  error: Error | undefined;
  nonce: number | undefined;
  hash: string | undefined;
}

export type MessageType = "mint" | "progress"

export type MintPayload = IWorkerTask

export type ProgressPayload = {
  id: string,
  hashRate: number,
}

export type EndPayload = {
  id: string,
  nonce: number | undefined,
  hash: string,
}