 module movescriptions::mrc721{
    use std::string::String;
    use std::option;
    use std::hash;
    use std::vector;
    use std::bcs;
    use moveos_std::context::{Self, Context};
    use moveos_std::table::{Self, Table};
    use moveos_std::object::{Self, Object};
    use moveos_std::object_id::{ObjectID};
    use movescriptions::movescription::{Self, TickInfo, TickRegistry};
    use movescriptions::merkle_proof;
    use movescriptions::util;

    const ErrorTickNotFound : u64 = 1;
    const ErrorNFTAlreadyMinted : u64 = 2;
    const ErrorMerkleProofInvalid : u64 = 3;

    /// The MRC721 is a protocol like ERC721
    struct MRC721 has key {
        tick_info: Object<TickInfo>,
        /// The item content type
        content_type: String,
        /// The merkle root of the item list
        merkle_root: vector<u8>,
        /// Merkle leaf index -> NFT object ID
        minted_nft: Table<u64, ObjectID>
    }

    struct MRC721Store has key{
        /// The tick to MRC721 Info Object
        ticks: Table<String, Object<MRC721>>,
    }

    fun init(ctx: &mut Context){
        let ticks = context::new_table(ctx);
        let store_obj = context::new_named_object(ctx, MRC721Store{
            ticks,
        });
        object::to_shared(store_obj);
    }


    fun do_deploy(ctx: &mut Context, registry_obj: &mut Object<TickRegistry>, store_obj: &mut Object<MRC721Store>, tick: String, difficulty: u64, content_type: String, merkle_root: vector<u8>) {
        let tick_info =  movescription::deploy(ctx, registry_obj, tick, difficulty);
        let mrc721 = MRC721 {
            tick_info: tick_info,
            merkle_root: merkle_root,
            content_type: content_type,
            minted_nft: context::new_table(ctx),
        };
        let unique_tick = util::to_lower_case(tick);
        let mrc721_store = object::borrow_mut(store_obj);
        let mrc721_obj = context::new_object(ctx, mrc721);
        table::add(&mut mrc721_store.ticks, unique_tick, mrc721_obj);
    }

    entry fun deploy(ctx: &mut Context, registry_obj: &mut Object<TickRegistry>, store_obj: &mut Object<MRC721Store>, tick: String, difficulty: u64, content_type: String, merkle_root: vector<u8>) {
        do_deploy(ctx, registry_obj, store_obj, tick, difficulty, content_type, merkle_root);
    }

    fun do_mint(ctx: &mut Context, store_obj: &mut Object<MRC721Store>, tick: String, nonce: u64, merkle_proof: vector<u8>, index: u64, value: u256, content: vector<u8>) {
        let sender = context::sender(ctx);
        let unique_tick = util::to_lower_case(tick);
        let mrc721_store = object::borrow_mut(store_obj);
        assert!(table::contains(&mrc721_store.ticks, unique_tick), ErrorTickNotFound);
        let mrc721_obj = table::borrow_mut(&mut mrc721_store.ticks, unique_tick);
        let mrc721 = object::borrow_mut(mrc721_obj);

        assert!(!table::contains(&mrc721.minted_nft, index), ErrorNFTAlreadyMinted);
        let content_hash = hash::sha3_256(content);
        let leaf = encode_leaf(&index, &value, content_hash);
        let proof = util::split_vector(&merkle_proof, 32);
        assert!(merkle_proof::verify(&proof, &mrc721.merkle_root, leaf), ErrorMerkleProofInvalid);
        
        let metadata = movescription::new_metadata(mrc721.content_type, content);
        let nftid = movescription::mint(ctx, sender, &mrc721.tick_info, nonce, value, option::some(metadata));
        table::add(&mut mrc721.minted_nft, index, nftid);
    } 

    entry fun mint(ctx: &mut Context, store_obj: &mut Object<MRC721Store>, tick: String, nonce: u64, merkle_proof: vector<u8>, index: u64, value: u256, content: vector<u8>) {
        do_mint(ctx, store_obj, tick, nonce, merkle_proof, index, value, content);
    } 

    fun encode_leaf(
        index: &u64,
        value: &u256,
        content_hash:vector<u8>,
    ): vector<u8> {
        let leaf = vector::empty();
        vector::append(&mut leaf, bcs::to_bytes(index));
        vector::append(&mut leaf, bcs::to_bytes(value));
        vector::append(&mut leaf, content_hash);
        leaf
    }
 }