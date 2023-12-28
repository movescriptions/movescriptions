import cpuWorkerUrl from './cpu-worker/index.ts?worker&url';
import gpuWorkerUrl from './gpu-worker/index.ts?worker&url';

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
  onSuccess: (result: IMintResult)=>void;
  onError: (err: Error)=>void;
  onProgress: (msg: string)=>void;
}

export interface IWorkerTask {
  powData: Uint8Array;
  difficulty: number;
  seqStart: number,
  seqEnd: number,
  timestamp: number;
}

export class MinerManager {
  status: Status;
  cpuWorkerCount: number;
  gpuWorkerCount: number;
  tasks: Array<IMinerTask>;
  cpuWorkers: Array<Worker>;
  gpuWorkers: Array<Worker>;
  taskTicker: number | NodeJS.Timeout | undefined;
  currentTask: IMinerTask | undefined

  constructor(cpuWorkerCount: number, gpuWorkerCount: number){
    this.status = Status.Idle;
    this.cpuWorkerCount = cpuWorkerCount;
    this.gpuWorkerCount = gpuWorkerCount;

    this.tasks = new Array<IMinerTask>();
    this.cpuWorkers = new Array<Worker>();
    this.gpuWorkers = new Array<Worker>();
    this.currentTask = undefined;
  }

  public addTask(task: IMinerTask) {
    this.tasks.push(task)
  }

  public isInit() {
    return this.status == Status.Init
  }

  public isRunning() {
    return this.status == Status.Runing
  }

  public start() {
    // init CPU workers
    for (let i=0; i<this.cpuWorkerCount; i++) {
      const cpuMineWorker = new Worker(cpuWorkerUrl, {
        type: 'module'
      });
      this.cpuWorkers.push(cpuMineWorker)
    }

    // init GPU workers
    for (let i=0; i<this.gpuWorkerCount; i++) {
      const gpuMineWorker = new Worker(gpuWorkerUrl, {
        type: 'module'
      });
      this.gpuWorkers.push(gpuMineWorker)
    }

    this.status == Status.Runing;

    this.taskTicker = setInterval(()=>{
      this.handleTask()
    }, 100)
  }

  public stop() {
    if (this.taskTicker) {
      clearInterval(this.taskTicker)
    }

    // Stop CPU workers
    this.cpuWorkers.forEach((worker: Worker) => {
        worker.terminate();
    });
    this.gpuWorkers = [];

    // Stop GPU workers
    this.gpuWorkers.forEach((worker: Worker) => {
        worker.terminate();
    });
    this.gpuWorkers = [];
  }

  private handleTask() {
    if (this.currentTask || this.tasks.length == 0) {
      return
    }

    const task = this.tasks.shift()
    if (task) {
      this.currentTask = task;

      const cpuSequencePerWorker = Math.floor(MAX_SEQUENCE / (this.cpuWorkerCount * 2));
      const gpuSequencePerWorker = Math.floor(MAX_SEQUENCE / (this.gpuWorkerCount * 4));
    
      let currentSeqStart = 0;
    
      for (let i = 0; i < this.cpuWorkerCount; i++) {
        const workerTask: IWorkerTask = {
          powData: task.powData,
          difficulty: task.difficulty,
          seqStart: currentSeqStart,
          seqEnd: currentSeqStart + cpuSequencePerWorker,
          timestamp: task.timestamp,
        };
  
        this.bindWorkerEvents(this.cpuWorkers[i], task)
        this.cpuWorkers[i].postMessage(workerTask);

        currentSeqStart += cpuSequencePerWorker;
      }
  
      for (let i = 0; i < this.gpuWorkerCount; i++) {
        const workerTask: IWorkerTask = {
          powData: task.powData,
          difficulty: task.difficulty,
          seqStart: currentSeqStart,
          seqEnd: currentSeqStart + gpuSequencePerWorker,
          timestamp: task.timestamp,
        };
  
        this.gpuWorkers[i].postMessage(workerTask);
        this.bindWorkerEvents(this.gpuWorkers[i], task)

        currentSeqStart += gpuSequencePerWorker;
      }
    }
  }

  private bindWorkerEvents(worker: Worker, task: IMinerTask) {
    worker.onmessage = (ev: MessageEvent)=>{
      console.log('msg:', ev)
      task.onProgress(ev.data)
    }

    worker.onerror = (ev: ErrorEvent)=>{
      console.log('msg:', ev)
      task.onError(new Error(ev.error))
    }
  }
}

