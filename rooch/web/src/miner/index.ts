import cpuWorkerUrl from './cpu-worker/index.ts?worker&url';
import gpuWorkerUrl from './gpu-worker/index.ts?worker&url';

export interface IMinerTask {
  id: string;
  powData: Uint8Array;
  difficulty: number;
  nonceStart: number;
  nonceEnd: number;
  timestamp: number;
  onSuccess: ()=>void;
  onError: ()=>void;
}

export class MinerManager {
  cpuWorkerCount: number;
  gpuWorkerCount: number;
  tasks: Array<IMinerTask>;
  cpuWorkers: Array<Worker>;
  gpuWorkers: Array<Worker>;

  constructor(cpuWorkerCount: number, gpuWorkerCount: number){
    this.cpuWorkerCount = cpuWorkerCount;
    this.gpuWorkerCount = gpuWorkerCount;

    this.tasks = new Array<IMinerTask>();
    this.cpuWorkers = new Array<Worker>();
    this.gpuWorkers = new Array<Worker>();
  }

  public addTask(task: IMinerTask) {
    this.tasks.push(task)
  }

  public start() {
    // init cpu workers
    for (let i=0; i<this.cpuWorkerCount; i++) {
      const cpuMineWorker = new Worker(cpuWorkerUrl, {
        type: 'module'
      });
      this.cpuWorkers.push(cpuMineWorker)
    }

    // init gpu workers
    for (let i=0; i<this.gpuWorkerCount; i++) {
      const gpuMineWorker = new Worker(gpuWorkerUrl, {
        type: 'module'
      });
      this.gpuWorkers.push(gpuMineWorker)
    }
  }
}

