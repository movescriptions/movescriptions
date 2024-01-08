import { v4 as uuidv4 } from 'uuid';
import cpuWorkerUrl from './cpu-worker/index.ts?worker&url';
import gpuWorkerUrl from './gpu-worker/index.ts?worker&url';

import { Status, IMinerTask, IWorkerTask, MAX_SEQUENCE } from './types'

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
    this.currentTask = undefined;

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
    this.tasks = [];

    this.status == Status.Idle;
  }

  private handleTask() {
    if (this.currentTask || this.tasks.length == 0) {
      return
    }

    const task = this.tasks.shift()
    if (task) {
      this.currentTask = task;
      let currentSeqStart = 0;
    
      if (this.cpuWorkerCount > 0) {
        const cpuSequencePerWorker = Math.floor(MAX_SEQUENCE / (this.cpuWorkerCount * 2));

        for (let i = 0; i < this.cpuWorkerCount; i++) {
          const workerTask: IWorkerTask = {
            id: uuidv4(),
            powData: task.powData,
            difficulty: task.difficulty,
            seqStart: currentSeqStart,
            seqEnd: currentSeqStart + cpuSequencePerWorker,
            timestamp: task.timestamp,
          };
    
          this.bindWorkerEvents(this.cpuWorkers[i], task)
          this.cpuWorkers[i].postMessage({
            type: "mint",
            payload: workerTask
          });
  
          currentSeqStart += cpuSequencePerWorker;
        }
      }
      
      if (this.gpuWorkerCount > 0) {
        for (let i = 0; i < this.gpuWorkerCount; i++) {
          const gpuSequencePerWorker = Math.floor(MAX_SEQUENCE / (this.gpuWorkerCount * 4));

          const workerTask: IWorkerTask = {
            id: uuidv4(),
            powData: task.powData,
            difficulty: task.difficulty,
            seqStart: currentSeqStart,
            seqEnd: currentSeqStart + gpuSequencePerWorker,
            timestamp: task.timestamp,
          };
    
          this.bindWorkerEvents(this.gpuWorkers[i], task)
          this.gpuWorkers[i].postMessage({
            type: "mint",
            payload: workerTask
          });

          currentSeqStart += gpuSequencePerWorker;
        }
      }
    }
  }

  private bindWorkerEvents(worker: Worker, task: IMinerTask) {
    worker.onmessage = (ev: MessageEvent)=>{
      const { type, payload } = ev.data;
      console.log('worker event:', type, 'payload:', payload)

      switch (type) {
        case "progress":
          task.onProgress(payload);
          break
        case "end":
            task.onEnd(payload);
            break
        default:
          console.log('not support type:', type)
      }
    }

    worker.onerror = (ev: ErrorEvent)=>{
      console.log('msg:', ev)
      task.onError(new Error(ev.error))
    }
  }
}

