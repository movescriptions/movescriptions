module movescriptions::movescription{
    use std::string::{Self, String};
    use std::option::Option;
    use std::bcs;
    use std::vector;
    use std::signer;
    use moveos_std::context::{Self, Context};
    use moveos_std::table::{Self, Table};
    use moveos_std::object::{Self, Object};
    use moveos_std::object_id::{ObjectID};
    use rooch_framework::hash;
    use rooch_framework::account;
    use movescriptions::util;

    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;

    const ErrorTickLengthInvaid: u64 = 1;
    const ErrorTickAlreadyExists: u64 = 2;
    const ErrorTickNotExists: u64 = 3;
    const ErrorInvalidPoW: u64 = 4;
    const ErrorMergeTickNotMatch: u64 = 5;
    const ErrorSplitValueTooLarge: u64 = 6;

    friend movescriptions::mrc20;
    friend movescriptions::mrc721;

    struct TickRegistry has key{
        /// The map of tick to TickInfo object id
        infos: Table<String, ObjectID>,
    }

    struct TickInfo has key, store {
        /// The Movescription's name, we need to make sure it's unique and case-insensitive
        /// length >= 4 && length <= 32
        tick: String,
        /// The PoW difficulty of the Movescription
        difficulty: u64,
    }

    struct Movescription has key, store{
        tick: String,
        value: u256,
        /// The metadata of the Movescription, it is optional 
        metadata: Option<Metadata>,
    }

    struct Metadata has store, copy, drop {
        /// The metadata content type, eg: image/png, image/jpeg, it is optional
        content_type: std::string::String,  
        /// The metadata content
        content: vector<u8>,
    }

    fun init(ctx: &mut Context){
        let infos = context::new_table(ctx);
        let registry_obj = context::new_named_object(ctx, TickRegistry{
            infos,
        });
        object::to_shared(registry_obj);
    }

    // === TicnInfo ===

    public fun tick(self: &TickInfo) : String {
        self.tick
    }

    public fun difficulty(self: &TickInfo) : u64 {
        self.difficulty
    }

    // === Metadata ===

    public(friend) fun new_metadata(content_type: String, content: vector<u8>) : Metadata {
        Metadata {
            content_type,
            content,
        }
    }
    
    public fun content_type(self: &Metadata) : String {
        self.content_type
    }

    public fun content(self: &Metadata) : vector<u8> {
        self.content
    }

    // === Movescription ===
    
    fun drop(self: Movescription){
        let Movescription{tick:_, value:_, metadata:_} = self;
    }

    //TODO make it public
    fun burn(movescription_obj: Object<Movescription>){
        //TODO should we reduce the total supply? 
        let movescription = object::remove(movescription_obj);
        drop(movescription);
    }

    public fun get_tick_info(registry_obj: &Object<TickRegistry>, tick: String) : ObjectID{
        let unique_tick = util::to_lower_case(tick);
        let registry = object::borrow(registry_obj);
        assert!(table::contains(&registry.infos, unique_tick), ErrorTickNotExists);
        *table::borrow(&registry.infos, unique_tick)
    }

    public(friend) fun deploy(ctx: &mut Context, registry_obj: &mut Object<TickRegistry>, tick: String, difficulty: u64) : Object<TickInfo>{
        let unique_tick = util::to_lower_case(tick);
        assert!(string::length(&unique_tick) >= MIN_TICK_LENGTH, ErrorTickLengthInvaid);
        assert!(string::length(&unique_tick) <= MAX_TICK_LENGTH, ErrorTickLengthInvaid);
        let registry = object::borrow_mut(registry_obj);
        assert!(!table::contains(&registry.infos, unique_tick), ErrorTickAlreadyExists);
        
        let info = TickInfo {
            tick: unique_tick,
            difficulty: difficulty,
        };
        let info_obj = context::new_object(ctx, info);
        let info_id = object::id(&info_obj);
        table::add(&mut registry.infos, unique_tick, info_id);
        info_obj
    }

    public(friend) fun mint(ctx: &mut Context, sender: address, info_obj: &Object<TickInfo>, nonce: u64, value: u256, metadata: Option<Metadata>) : ObjectID{
       let info = object::borrow(info_obj);
        assert!(validate_pow(ctx, sender, info.tick, value, info.difficulty, nonce), ErrorInvalidPoW);
        let movescription = Movescription {
            tick: info.tick,
            value: value,
            metadata: metadata,
        };
        let movescription_obj = context::new_object(ctx, movescription);
        let object_id = object::id(&movescription_obj);
        object::transfer(movescription_obj, sender);
        object_id
    }


    fun do_merge(ctx: &mut Context, owner: address, first_movescription_obj: Object<Movescription>, second_movescription_obj: Object<Movescription>){
        let first_movescription = object::remove(first_movescription_obj);
        let second_movescription = object::remove(second_movescription_obj);
        assert!(first_movescription.tick == second_movescription.tick, ErrorMergeTickNotMatch);
        assert!(first_movescription.metadata == second_movescription.metadata, ErrorMergeTickNotMatch);
        let merged_value = first_movescription.value + second_movescription.value;
        let merged_metadata = first_movescription.metadata;
        let merged_movescription = Movescription {
            tick: first_movescription.tick,
            value: merged_value,
            metadata: merged_metadata,
        };
        let merged_movescription_obj = context::new_object(ctx, merged_movescription);
        object::transfer(merged_movescription_obj, owner);
        drop(first_movescription);
        drop(second_movescription);
    } 

    entry fun merge(ctx: &mut Context, sender: &signer, first_movescription: ObjectID, second_movescription: ObjectID){
        let first_movescription_obj = context::take_object<Movescription>(ctx, sender, first_movescription);
        let second_movescription_obj = context::take_object<Movescription>(ctx, sender, second_movescription);
        let owner = signer::address_of(sender);
        do_merge(ctx, owner, first_movescription_obj, second_movescription_obj);
    }

    fun do_split(ctx: &mut Context, owner: address, movescription_obj: Object<Movescription>, value: u256){
        let movescription = object::remove(movescription_obj);
        // We do not support >= here, because we want to make sure the value is not 0
        assert!(movescription.value > value, ErrorSplitValueTooLarge);
        let first_value = movescription.value - value;
        let second_value = value;
        let first_movescription = Movescription {
            tick: movescription.tick,
            value: first_value,
            metadata: movescription.metadata,
        };
        let second_movescription = Movescription {
            tick: movescription.tick,
            value: second_value,
            metadata: movescription.metadata,
        };
        let first_movescription_obj = context::new_object(ctx, first_movescription);
        let second_movescription_obj = context::new_object(ctx, second_movescription);
        object::transfer(first_movescription_obj, owner);
        object::transfer(second_movescription_obj, owner);
        drop(movescription);
    }

    entry fun split(ctx: &mut Context, sender: &signer, movescription: ObjectID, value: u256){
        let movescription_obj = context::take_object<Movescription>(ctx, sender, movescription);
        let owner = signer::address_of(sender);
        do_split(ctx, owner, movescription_obj, value);
    }
    

    public fun validate_pow(ctx: &Context, sender: address, tick: String, value: u256, difficulty: u64, nonce: u64) : bool {
        let data = pow_input(ctx, sender, tick, value);
        let data_hash = hash::keccak256(&data);
        vector::append(&mut data_hash, bcs::to_bytes(&nonce));
        std::debug::print(&data_hash);
        let hash = hash::keccak256(&data_hash);
        std::debug::print(&hash);
        let i = 0; 
        while(i < difficulty) {
            if(*vector::borrow(&hash, i) != 0){
                return false
            };
            i = i + 1;
        };
        true
    }

    public fun pow_input(ctx: &Context, sender: address,  tick: String, value: u256) : vector<u8> {
        let sequence_number = account::sequence_number(ctx, sender);

        let data = vector::empty();
        vector::append(&mut data, *string::bytes(&tick));
        vector::append(&mut data, bcs::to_bytes(&value));

        vector::append(&mut data, bcs::to_bytes(&sender));
        vector::append(&mut data, bcs::to_bytes(&sequence_number));
        std::debug::print(&data);
        //TODO should we add a timestamp here?
        data
    }

    #[test]
    fun test_nonce(){
        std::debug::print(&bcs::to_bytes(&1));
        std::debug::print(&bcs::to_bytes(&2));
    }
}