

export const MAX_SEQUENCE = Number.MAX_SAFE_INTEGER;

export enum Status {
  Init,
  Idle,
  Runing
}

export interface IMintResult {
  nonce: number;
  hash: string;
}

export interface IMintProgress {
  name: string;
  hash?: string;
  nonce?: number;
  hashRate: number;
  details?: Array<IMintProgress>
}

export interface IMinerTask {
  id: string;
  powData: Uint8Array;
  difficulty: number;
  timestamp: number;
  onEnd: (result: IMintResult)=>void;
  onError: (err: Error)=>void;
  onProgress: (msg: IMintProgress)=>void;
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
  progress?: IMintProgress;
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