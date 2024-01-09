use fastcrypto::hash::{HashFunction, Keccak256};
use tracing::trace;

fn hash<H: HashFunction<DIGEST_SIZE>, const DIGEST_SIZE: usize>(data: &[u8]) -> [u8; DIGEST_SIZE] {
    H::digest(data).digest
}

pub fn keccak256(data: &[u8]) -> [u8; 32] {
    hash::<Keccak256, 32>(data)
}

pub fn pow(input: &[u8], difficulty: u64) -> ([u8; 32], u64) {
    let mut nonce = 0u64;
    let input_data_hash = keccak256(input);
    let mut bytes = [0; 40];
    bytes[..32].copy_from_slice(&input_data_hash);
    loop {
        bytes[32..].copy_from_slice(&nonce.to_le_bytes());
        let hash = keccak256(&bytes);
        for (i, b) in hash.iter().enumerate() {
            if *b != 0 {
                if i < difficulty as usize {
                    break;
                } else {
                    trace!("found hash bytes: {}", hex::encode(bytes));
                    return (hash, nonce);
                }
            }
        }
        if (nonce % 100000) == 0 {
            print!("\rNonce: {}", nonce);
        }
        nonce += 1;
    }
}

pub fn pow_hash(input: &[u8], nonce: u64) -> [u8; 32] {
    let input_data_hash = keccak256(input);
    let mut bytes = [0; 40];
    bytes[..32].copy_from_slice(&input_data_hash);
    bytes[32..].copy_from_slice(&nonce.to_le_bytes());
    keccak256(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn do_pow_test(input: &[u8], difficulty: u64) {
        let start_time = std::time::Instant::now();
        let (hash, nonce) = pow(input, difficulty);
        println!(
            "difficulty: {}, hash: {}, nonce: {}",
            difficulty,
            hex::encode(hash),
            nonce
        );
        assert!(hash.iter().take(difficulty as usize).all(|b| *b == 0));
        println!("time: {}ms", start_time.elapsed().as_millis());
    }

    #[test]
    fn test_pow() {
        let data = b"hello world";
        do_pow_test(data, 1);
        //do_pow_test(data, 2);
        //do_pow_test(data, 3);
        //do_pow_test(data, 4);
    }

    #[test]
    fn test_nonce(){
        println!("nonce: {}", hex::encode(1u64.to_le_bytes()));
        println!("nonce: {}", hex::encode(2u64.to_le_bytes()));
    }

    #[test]
    fn test_hash(){
        let data = hex::decode("00").unwrap();
        let hash = keccak256(&data);
        assert_eq!(hex::encode(hash), "bc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a");
    }

    #[test]
    fn test_pow2(){
        let data = hex::decode("00").unwrap();
        let hash = pow_hash(&data, 1);
        assert_eq!(hex::encode(hash), "dac9acd0a27c1b2b2ea7337c7db91f10a0b2d0021b3396d6cf17ea440d44f3de");
    }

    #[test]
    fn test_pow3(){
        let data = hex::decode("01").unwrap();
        let hash = pow_hash(&data, 1);
        assert_eq!(hex::encode(hash), "62b37b4426cc078150de8cd78cd7ae786d20d03d54e59d0997ab90a5f4e6e5dd");
    }

    #[test]
    fn test_pow4(){
        let data = hex::decode("4c6d6f7665e8030000000000000000000000000000000000000000000000000000000000007194e6bf0860250491496174e7f7d7a9a9424d41734830656b9466787c04480c0000000000000000").unwrap();
        let hash = pow_hash(&data, 1342185966);
        assert_eq!(hex::encode(hash), "00006e5917a8966d8b9a9cfc7d85404d3b6da67ec2ed850e03c7c5e5fa7e3e15");
    }
}
