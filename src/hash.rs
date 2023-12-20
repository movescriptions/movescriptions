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
        do_pow_test(data, 2);
        do_pow_test(data, 3);
        do_pow_test(data, 4);
    }

    #[test]
    fn test_nonce(){
        println!("nonce: {}", hex::encode(1u64.to_le_bytes()));
        println!("nonce: {}", hex::encode(2u64.to_le_bytes()));
    }
}
