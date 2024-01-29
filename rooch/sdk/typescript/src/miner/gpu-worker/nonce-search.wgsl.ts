export function shader(device: GPUDevice): string {
  return `
  const KECCAK_ROUND = 24;
  const KECCAK256_INPUT_BUF_SIZE:u32 = 32; // 32 * 32bit
  const KECCAK256_OUTPUT_SIZE:u32 = 8; // 8 * 32bit

  // Keccak-256 round constants
  const SHA3_PI = array<u32, 24>(
    20, 14, 22, 34, 36, 6, 10, 32, 16, 42, 48, 8, 30, 46, 38, 26, 24, 4, 40, 28, 44, 18, 12, 2
  );

  const SHA3_ROTL = array<u32, 24>(
    1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44
  );

  const SHA3_IOTA_H = array<u32, 24>(
    1, 32898, 32906, 2147516416, 32907, 2147483649, 2147516545, 32777, 138, 136, 2147516425, 2147483658, 2147516555, 139, 32905, 32771, 32770, 128, 32778, 2147483658, 2147516545, 32896, 2147483649, 2147516424
  );
  
  const SHA3_IOTA_L = array<u32, 24>(
    0, 0, 2147483648, 2147483648, 0, 0, 2147483648, 2147483648, 0, 0, 0, 0, 0, 2147483648, 2147483648, 2147483648, 2147483648, 2147483648, 0, 2147483648, 2147483648, 2147483648, 0, 2147483648
  );

  // Left rotation (without 0, 32, 64)
  fn rotlH(h: u32, l: u32, s: u32) -> u32 {
    if (s > 32) {
      return (l << (s - 32)) | (h >> (64 - s));
    } else {  
      return (h << s) | (l >> (32 - s));
    }
  }
  
  fn rotlL(h: u32, l: u32, s: u32) -> u32 {
    if (s > 32) {
      return (h << (s - 32)) | (l >> (64 - s));
    } else {
      return (l << s) | (h >> (32 - s));
    }
  }

  fn xorHigh8bits(data: u32, value: u32) -> u32 {
    return (data & 0x00FFFFFFu) | ((data ^ (value << 24)) & 0xFF000000u);
  }

  fn xorLow8bits(data: u32, value: u32) -> u32 {
    return (data & 0xFFFFFFu) | ((data ^ value) & 0xFFu);
  }

  fn to_big_endian(value: u32) -> u32 {
    var result: u32;

    result = ((value & 0x000000FFu) << 24u) |
             ((value & 0x0000FF00u) << 8u) |
             ((value & 0x00FF0000u) >> 8u) |
             ((value & 0xFF000000u) >> 24u);

    return result;
  }

  struct Keccak {
    state: array<u32, 50>,
    blockLen: u32,
    suffix: u32,
    outputLen: u32,
    pos: u32,
    posOut: u32
  }

  fn keccak_keccak(ctx: ptr<function, Keccak>) {
    var B: array<u32, 10>;

    for (var round: u32 = 0; round < KECCAK_ROUND; round = round + 1) {
      // Theta
      for (var x: u32 = 0; x < 10; x = x + 1) {
        B[x] = (*ctx).state[x] ^ (*ctx).state[x+10] ^ (*ctx).state[x+20] ^ (*ctx).state[x+30] ^ (*ctx).state[x+40]; 
      }

      for (var x:u32 = 0; x < 10; x += 2) {
        let idx0 = (x + 2) % 10;
        let idx1 = (x + 8) % 10;

        let B0 = B[idx0];
        let B1 = B[idx0 + 1];

        let Th = rotlH(B0, B1, 1) ^ B[idx1];
        let Tl = rotlL(B0, B1, 1) ^ B[idx1 + 1];

        for (var y:u32 = 0; y < 50; y += 10) {
          (*ctx).state[x + y] ^= Th;
          (*ctx).state[x + y + 1] ^= Tl;
        }
      }

      // Rho Pi
      var curH: u32 = (*ctx).state[2];
      var curL: u32 = (*ctx).state[3];
      
      for (var t: u32 = 0; t < 24; t = t + 1) {
        let shift: u32 = SHA3_ROTL[t];
        let Th: u32 = rotlH(curH, curL, shift);
        let Tl: u32 = rotlL(curH, curL, shift);
      
        let PI: u32 = SHA3_PI[t];
        curH = (*ctx).state[PI];
        curL = (*ctx).state[PI + 1];
      
        (*ctx).state[PI] = Th;
        (*ctx).state[PI + 1] = Tl; 
      }
  
      // Chi
      for (var y: u32 = 0; y < 50; y = y + 10) {
        for (var x: u32 = 0; x < 10; x = x + 1) {
          B[x] = (*ctx).state[y + x];
        }
        
        for (var x: u32 = 0; x < 10; x = x + 1) {
          (*ctx).state[y + x] ^= ~B[(x + 2) % 10] & B[(x + 4) % 10];  
        }
      }
  
      // Iota
      (*ctx).state[0] ^= SHA3_IOTA_H[round];
      (*ctx).state[1] ^= SHA3_IOTA_L[round];
    }

    (*ctx).posOut = 0;
    (*ctx).pos = 0;
  }

  fn keccak_update(ctx: ptr<function, Keccak>, input: ptr<function, array<u32, KECCAK256_INPUT_BUF_SIZE>>, input_len:u32) {
    var pos: u32 = 0;

    while(pos < input_len) {
      var take = min((*ctx).blockLen - (*ctx).pos, input_len - pos);
  
      for(var i:u32 = 0; i < take; i++) {
        (*ctx).state[(*ctx).pos] ^= (*input)[pos];
        (*ctx).pos = (*ctx).pos + 1;
        pos = pos + 1;
      }
  
      if ((*ctx).pos == (*ctx).blockLen) {
        keccak_keccak(ctx);
      }
    }
  }

  fn keccak_finish(ctx: ptr<function, Keccak>) {
    (*ctx).state[(*ctx).pos] = xorLow8bits((*ctx).state[(*ctx).pos], (*ctx).suffix);
  
    if ( ((*ctx).suffix & 0x80) != 0 && (*ctx).pos == (*ctx).blockLen - 1) {
      keccak_keccak(ctx);
    }
  
    (*ctx).state[(*ctx).blockLen-1] = xorHigh8bits((*ctx).state[(*ctx).blockLen-1], 0x80);
  
    keccak_keccak(ctx);
  }

  fn keccak_output(ctx: ptr<function, Keccak>, output: ptr<function, array<u32, KECCAK256_OUTPUT_SIZE>>) {
    for(var pos:u32 = 0; pos < (*ctx).outputLen;) {
      if ((*ctx).posOut >= (*ctx).blockLen) {
        keccak_keccak(ctx);
      }

      var take = min((*ctx).blockLen - (*ctx).posOut, (*ctx).outputLen - pos);

      for(var i:u32 = 0; i < take; i++) {
        (*output)[pos] = (*ctx).state[(*ctx).posOut];
        (*ctx).posOut = (*ctx).posOut + 1;
        pos = pos + 1;
      }
    }
  }

  // Keccak-256 hash function
  fn keccak256(input: ptr<function, array<u32, KECCAK256_INPUT_BUF_SIZE>>, input_len:u32, output: ptr<function, array<u32, KECCAK256_OUTPUT_SIZE>>) {
    var ctx: Keccak;

    // keccak-256 hash function params
    ctx.suffix = 0x01;
    ctx.blockLen = 136 / 4; // 34*32bit
    ctx.outputLen = KECCAK256_OUTPUT_SIZE;

    // init state
    ctx.state = array<u32, 50>(/*zeros*/); // 1600 = 5x5 matrix of 64bit.  1600 bits === 200 bytes, 50 32bit
    ctx.pos = 0;
    ctx.posOut = 0;

    // calc hash
    keccak_update(&ctx, input, input_len);
    keccak_finish(&ctx);
    keccak_output(&ctx, output);
  }
  
  fn check_difficulty_bytes(hash: array<u32, 8>, n: u32) -> bool {
    var byte_index: u32 = n / 4;
    var remainder: u32 = n % 4;

    for (var i: u32 = 0; i < byte_index; i++) {
      if (hash[i] != 0u) { return false; }
    }

    if (remainder != 0u) {
      var mask: u32 = 0xFFFFFFFFu << ((4 - remainder) * 8u);
      if ((to_big_endian(hash[byte_index]) & mask) != 0u) { return false; }
    }

    return true;
  }

  fn check_difficulty_bits(hash: array<u32, 8>, n: u32) -> bool {
    var byte_index: u32 = n / 32;
    var bit_index: u32 = n % 32;

    for (var i: u32 = 0; i < byte_index; i++) {
      if (hash[8 - i] != 0u) { return false; }
    }

    if (to_big_endian(hash[8 - byte_index]) % (1u << bit_index) == 0u) { 
      return true; 
    }

    return false;
  }

  @group(0) @binding(0) var<storage, read> key : array<u32>;
  @group(0) @binding(1) var<storage, read> difficulty : u32;
  @group(0) @binding(2) var<storage, read_write> output: array<u32>;
  @group(0) @binding(3) var<storage, read_write> output_count: atomic<u32>;
  @group(0) @binding(4) var<storage, read_write> log_buffer: array<u32>;

  @compute @workgroup_size(${device.limits.maxComputeWorkgroupSizeX})
  fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    var key_len = arrayLength(&key);
    var input : array<u32, KECCAK256_INPUT_BUF_SIZE> = array<u32, KECCAK256_INPUT_BUF_SIZE>();
    var hash : array<u32, KECCAK256_OUTPUT_SIZE> =  array<u32, KECCAK256_OUTPUT_SIZE>();

    for (var i: u32 = 0; i < key_len; i = i + 1u) {
      input[i] = key[i];
    }

    var nonce = global_id.x;
    input[key_len-2] = nonce;

    keccak256(&input, key_len, &hash);
  
    if (check_difficulty_bytes(hash, difficulty)) {
      var index = atomicAdd(&output_count, 1);
      if (index < arrayLength(&output)) {
        output[index] = nonce;
      }

      if (index == 1) {
        for (var i: u32 = 0; i < key_len; i = i + 1u) {
          log_buffer[i] = input[i];
        }

        for (var i:u32 = key_len; i < key_len + KECCAK256_OUTPUT_SIZE; i = i + 1u) {
          log_buffer[i] = hash[i];
        }
      }
    }
  }
`;
}
