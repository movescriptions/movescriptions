import { shader } from './nonce-search.wgsl';
import { u32 } from './types';
const debug = false;

async function getGPUDevice(): Promise<GPUDevice> {
  const adapter = await navigator.gpu.requestAdapter({
    powerPreference: 'high-performance',
  });
  if (!adapter) {
    throw 'No adapter';
  } else {
    return await adapter.requestDevice();
  }
}

function calcNumWorkgroups(device: GPUDevice, taskNum: number): number {
  const numWorkgroups = Math.ceil(
    taskNum / device.limits.maxComputeWorkgroupSizeX
  );
  if (numWorkgroups > device.limits.maxComputeWorkgroupsPerDimension) {
    throw `Input array too large. Max size is ${
      device.limits.maxComputeWorkgroupsPerDimension *
      device.limits.maxComputeWorkgroupSizeX
    }.`;
  }
  return numWorkgroups;
}

function padMessage(bytes: Uint8Array, size: number): Uint32Array {
  const arrBuff = new ArrayBuffer(size * 4);
  new Uint8Array(arrBuff).set(bytes);
  return new Uint32Array(arrBuff);
}

function check(key: Uint8Array) {
  if (key.length % 4 !== 0) throw 'Message must be 32-bit aligned';
}

class GPU {
  #device: GPUDevice | null = null;
  #computePipeline: GPUComputePipeline | null = null;

  async init() {
    this.#device = await getGPUDevice();
    this.#computePipeline = this.#device.createComputePipeline({
      compute: {
        module: this.#device.createShaderModule({ code: shader(this.#device) }),
        entryPoint: 'main',
      },
      layout: 'auto',
    });
    return this;
  }

  get device() {
    if (!this.#device) {
      throw new Error('Device is not initialized');
    }
    return this.#device;
  }

  get computePipeline() {
    if (!this.#computePipeline) {
      throw new Error('Compute pipeline is not initialized');
    }
    return this.#computePipeline;
  }
}

let gpu: GPU;

/**
 * Init GPU
 *
 */
export async function gpu_init() {
  return gpu ? gpu : await new GPU().init();
}

/**
 * Batch Search Nonce
 *
 * @param {Uint8Array[]} messages messages to hash. Each message must be 32-bit aligned with the same size
 * @returns {Uint8Array} the set of resulting hashes
 */
export async function nonce_search(key: Uint8Array, difficulty: number) {
  check(key);

  gpu = await gpu_init();

  const nonceStart = 0;
  const nonceEnd = gpu.device.limits.maxComputeWorkgroupSizeX;

  const numWorkgroups = calcNumWorkgroups(gpu.device, nonceEnd - nonceStart);

  // key
  const u32KeyArray = padMessage(key, key.length / 4);
  const keyBuffer = gpu.device.createBuffer({
    mappedAtCreation: true,
    size: u32KeyArray.byteLength,
    usage: GPUBufferUsage.STORAGE,
  });
  new Uint32Array(keyBuffer.getMappedRange()).set(u32KeyArray);
  keyBuffer.unmap();

  // nonceStart
  const nonceStartBuffer = gpu.device.createBuffer({
    mappedAtCreation: true,
    size: Uint32Array.BYTES_PER_ELEMENT,
    usage: GPUBufferUsage.STORAGE,
  });
  new Uint32Array(nonceStartBuffer.getMappedRange()).set([nonceStart]);
  nonceStartBuffer.unmap();

  // nonceEnd
  const nonceEndBuffer = gpu.device.createBuffer({
    mappedAtCreation: true,
    size: Uint32Array.BYTES_PER_ELEMENT,
    usage: GPUBufferUsage.STORAGE,
  });
  new Uint32Array(nonceEndBuffer.getMappedRange()).set([nonceEnd]);
  nonceEndBuffer.unmap();

  // difficulty
  const difficultyBuffer = gpu.device.createBuffer({
    mappedAtCreation: true,
    size: Uint32Array.BYTES_PER_ELEMENT,
    usage: GPUBufferUsage.STORAGE,
  });
  new Uint32Array(difficultyBuffer.getMappedRange()).set([difficulty]);
  difficultyBuffer.unmap();

  // Result
  const resultSize = 1024;
  const resultBuffer = gpu.device.createBuffer({
    size: resultSize,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC,
  });

  // Result count
  const resultCountBuffer = gpu.device.createBuffer({
    size: Uint32Array.BYTES_PER_ELEMENT,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC,
  });

  // Log Buffer
  const logBufferSize = 256;
  const logBuffer = gpu.device.createBuffer({
    size: logBufferSize,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC,
  });

  const bindGroup = gpu.device.createBindGroup({
    layout: gpu.computePipeline.getBindGroupLayout(0),
    entries: [
      {
        binding: 0,
        resource: {
          buffer: keyBuffer,
        },
      },
      {
        binding: 1,
        resource: {
          buffer: nonceStartBuffer,
        },
      },
      {
        binding: 2,
        resource: {
          buffer: nonceEndBuffer,
        },
      },
      {
        binding: 3,
        resource: {
          buffer: difficultyBuffer,
        },
      },
      {
        binding: 4,
        resource: {
          buffer: resultBuffer,
        },
      },
      {
        binding: 5,
        resource: {
          buffer: resultCountBuffer,
        },
      },
      {
        binding: 6,
        resource: {
          buffer: logBuffer,
        },
      },
    ],
  });

  const commandEncoder = gpu.device.createCommandEncoder();

  const passEncoder = commandEncoder.beginComputePass();
  passEncoder.setPipeline(gpu.computePipeline);
  passEncoder.setBindGroup(0, bindGroup);
  passEncoder.dispatchWorkgroups(numWorkgroups);
  passEncoder.end();

  const gpuResultBuffer = gpu.device.createBuffer({
    size: resultSize,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
  });
  commandEncoder.copyBufferToBuffer(
    resultBuffer,
    0,
    gpuResultBuffer,
    0,
    resultSize
  );

  const gpuResultCountBuffer = gpu.device.createBuffer({
    size: 4,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
  });
  commandEncoder.copyBufferToBuffer(
    resultCountBuffer,
    0,
    gpuResultCountBuffer,
    0,
    4
  );

  const gpuLogReadBuffer = gpu.device.createBuffer({
    size: logBufferSize,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
  });
  commandEncoder.copyBufferToBuffer(
    logBuffer,
    0,
    gpuLogReadBuffer,
    0,
    logBufferSize
  );

  const gpuCommands = commandEncoder.finish();
  gpu.device.queue.submit([gpuCommands]);

  await gpuResultBuffer.mapAsync(GPUMapMode.READ);
  await gpuResultCountBuffer.mapAsync(GPUMapMode.READ);
  await gpuLogReadBuffer.mapAsync(GPUMapMode.READ);

  if (debug) {
    const logContent = new Uint8Array(gpuLogReadBuffer.getMappedRange());
    console.log('[Shader Log]:', logContent);
    console.log('[Shader Log]:', u32(logContent));
    console.log(
      '[Shader Log]:',
      '0x' +
        logContent
          .subarray(0, 32)
          .reduce((a: any, b: any) => a + b.toString(16).padStart(2, '0'), '')
    );
  }

  const result = new Array<number>();
  const count = new Uint32Array(gpuResultCountBuffer.getMappedRange())[0];
  if (count > 0) {
    const resultBuf = new Uint32Array(gpuResultBuffer.getMappedRange());
    for (let i = 0; i < count; i++) {
      result.push(resultBuf[i]);
    }
  }
  return result;
}
