import { v4 as uuidv4 } from 'uuid';
import { Status, IMinerTask, IMintProgress, IWorkerTask, IWorkerStatus, MAX_SEQUENCE } from './types'

export class MinerManager {
  status: Status;
  cpuWorkerCount: number;
  gpuWorkerCount: number;
  tasks: Array<IMinerTask>;
  cpuWorkers: Array<Worker>;
  gpuWorkers: Array<Worker>;
  workerStatus: Map<string, IWorkerStatus>;
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
    this.workerStatus = new Map<string, IWorkerStatus>();
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
      const cpuMineWorker = new Worker(new URL("./cpu-worker/index.worker.ts", import.meta.url), {
        type: "module",
      });
      this.cpuWorkers.push(cpuMineWorker)
    }

    // init GPU workers
    for (let i=0; i<this.gpuWorkerCount; i++) {
      const gpuMineWorker = new Worker(new URL("./gpu-worker/index.worker.ts", import.meta.url), {
        type: "module",
      });
      this.gpuWorkers.push(gpuMineWorker)
    }

    this.status == Status.Runing;

    this.taskTicker = setInterval(()=>{
      this.handleTask()
    }, 100)
  }

  public stop() {
    console.log("stop mint")

    this.currentTask = undefined;
    this.workerStatus = new Map<string, IWorkerStatus>();

    if (this.taskTicker) {
      clearInterval(this.taskTicker)
      this.taskTicker = undefined;
    }

    // Stop CPU workers
    this.cpuWorkers.forEach((worker: Worker) => {
        console.log("stop ", worker)
        worker.postMessage({
          type: "stop",
          payload: {}
        });

        worker.terminate();
    });
    this.cpuWorkers = [];

    // Stop GPU workers
    this.gpuWorkers.forEach((worker: Worker) => {
        console.log("stop ", worker)
        worker.postMessage({
          type: "stop",
          payload: {}
        });

        worker.terminate();
    });
    this.gpuWorkers = [];

    this.tasks = [];
    this.status == Status.Idle;
  }

  private handleTask() {
    if (this.currentTask) {
      this.collectTaskResult(this.currentTask)
      return
    }

    if (this.tasks.length == 0) {
      return
    }

    const task = this.tasks.shift()
    if (task) {
      console.log("handle task:", task)

      this.currentTask = task;
      let currentSeqStart = 0;
    
      const sequencePerWorker = Math.floor(MAX_SEQUENCE / (this.cpuWorkerCount + this.gpuWorkerCount * 10 + 3));

      if (this.cpuWorkerCount > 0) {
        currentSeqStart += sequencePerWorker * 3;

        for (let i = 0; i < this.cpuWorkerCount; i++) {
          const workerTask: IWorkerTask = {
            id: uuidv4(),
            powData: task.powData,
            difficulty: task.difficulty,
            seqStart: currentSeqStart,
            seqEnd: currentSeqStart + sequencePerWorker,
            timestamp: task.timestamp,
          };
    
          const workerStatus = {hashRate: 0, error: undefined, nonce: undefined, hash: undefined}
          this.bindWorkerEvents(this.cpuWorkers[i], workerStatus)
          this.workerStatus.set(workerTask.id, workerStatus)
          this.cpuWorkers[i].postMessage({
            type: "mint",
            payload: workerTask
          });
  
          currentSeqStart += sequencePerWorker;
        }
      }
      
      if (this.gpuWorkerCount > 0) {
        for (let i = 0; i < this.gpuWorkerCount; i++) {
          const workerTask: IWorkerTask = {
            id: uuidv4(),
            powData: task.powData,
            difficulty: task.difficulty,
            seqStart: currentSeqStart,
            seqEnd: currentSeqStart + sequencePerWorker * 10,
            timestamp: task.timestamp,
          };
    
          const workerStatus = {hashRate: 0, error: undefined, nonce: undefined, hash: undefined}
          this.bindWorkerEvents(this.gpuWorkers[i], workerStatus)
          this.workerStatus.set(workerTask.id, workerStatus)
          this.gpuWorkers[i].postMessage({
            type: "mint",
            payload: workerTask
          });

          currentSeqStart += sequencePerWorker;
        }
      }
    }
  }

  private bindWorkerEvents(worker: Worker, workerStatus: IWorkerStatus) {
    worker.onmessage = (ev: MessageEvent)=>{
      const { type, payload } = ev.data;
      console.log('worker event:', type, 'payload:', payload)

      switch (type) {
        case "progress":
          workerStatus.progress = payload;
          break
        case "end":
          workerStatus.nonce = payload.nonce;
          workerStatus.hash = payload.hash;
          break
        default:
          console.log('not support type:', type)
      }
    }

    worker.onerror = (ev: ErrorEvent)=>{
      workerStatus.error = new Error(ev.error);
    }
  }

  private collectTaskResult(task: IMinerTask) {
    let totalHashRate = 0;
    let lastHash: string | undefined = "";
    let lastNonce: number | undefined = 0;

    let details = new Array<IMintProgress>();

    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    for (const [_id, status] of this.workerStatus) {
      if (status.error) {
        task.onError(status.error)
        break
      }

      if (status.nonce && status.hash) {
        task.onEnd({
          nonce: status.nonce,
          hash: status.hash,
        });

        break
      }

      if (status.progress) {
        details.push(status.progress)
  
        lastHash = status.hash;
        lastNonce = status.nonce;
        totalHashRate = totalHashRate + status.progress.hashRate
      }
    }

    task.onProgress({
      name: "miner",
      hash: lastHash,
      nonce: lastNonce,
      hashRate: totalHashRate,
      details: details,
    });
  }
}
