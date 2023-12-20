//https://github.com/movefuns/movefuns/edit/main/starcoin/sources/MerkleDistributor.move
module movescriptions::merkle_proof {
    use std::compare;
    use std::hash;
    use std::vector;
  
    /// verify leaf node with `proof` againest merkle `root`.
    public fun verify(
        proof: &vector<vector<u8>>,
        root: &vector<u8>,
        leaf: vector<u8>
    ): bool {
        let computed_hash = hash::sha3_256(leaf);
        let i = 0;
        let proof_length = vector::length(proof);
        while (i < proof_length) {
            let sibling = vector::borrow(proof, i);
            // computed_hash is left.
            if (compare::cmp_bcs_bytes(&computed_hash, sibling) < 2) {
                let concated = concat(computed_hash, *sibling);
                computed_hash = hash::sha3_256(concated);
            } else {
                let concated = concat(*sibling, computed_hash);
                computed_hash = hash::sha3_256(concated);
            };

            i = i + 1;
        };
        &computed_hash == root
    }


    fun concat(v1: vector<u8>, v2: vector<u8>): vector<u8> {
        vector::append(&mut v1, v2);
        v1
    }
}