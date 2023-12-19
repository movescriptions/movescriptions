module movescription::movescription{
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::bcs;
    use std::vector;
    use moveos_std::context::{Self, Context};
    use moveos_std::table::{Self, Table};
    use moveos_std::object::{Self, Object, ObjectID};
    use rooch_framework::hash;
    use rooch_framework::account;

    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;

    const ErrorTickLengthInvaid: u64 = 1;
    const ErrorTickAlreadyExists: u64 = 2;
    const ErrorTickNotExists: u64 = 3;
    const ErrorMintExceedsLimit: u64 = 4;
    const ErrorMintExceedsMax: u64 = 5;
    const ErrorInvalidPoW: u64 = 6;


    struct MovescriptionRegistry has key{
        infos: Table<String, Supply>,
    }

    struct MovescriptionInfo<P: store> has key, store {
        /// The Movescription's name, we need to make sure it's unique and case-insensitive
        /// length >= 4
        tick: std::string::String,
        protocol: P,
        /// The PoW difficulty of the Movescription
        difficulty: u64,
    }

    struct Movescription has key, store{
        tick: std::string::String,
        value: u256,
        /// The metadata of the Movescription, it is optional 
        metadata: Option<Metadata>,
    }

    /// The MRC20 is a protocol like ERC20, BRC20, etc.
    /// The name is not a good name, but we follow the community's convention
    struct MRC20 has store, copy{
        /// The total supply of the MRC20
        max: u256,
        /// The limit of per MRC20 mint
        limit: u256,
        /// The decimals of the MRC20
        decimals: u64,
    }

    struct Metadata has store, copy, drop {
        /// The metadata content type, eg: image/png, image/jpeg, it is optional
        content_type: std::string::String,  
        /// The metadata content
        content: vector<u8>,
    }

    struct Supply has store{
        info_id: ObjectID,
        value: u256,
    }

    fun init(ctx: &mut Context){
        let infos = context::new_table(ctx);
        let registry_obj = context::new_named_object(ctx, MovescriptionRegistry{
            infos,
        });
        object::to_shared(registry_obj);
    }

    entry fun deploy_mrc20(ctx: &mut Context, registry_obj: &mut Object<MovescriptionRegistry>, tick: String, difficulty: u64, max: u256, limit: u256, decimals: u64) {
        let unique_tick = to_lower_case(tick);
        assert!(string::length(&unique_tick) >= MIN_TICK_LENGTH, ErrorTickLengthInvaid);
        assert!(string::length(&unique_tick) <= MAX_TICK_LENGTH, ErrorTickLengthInvaid);
        let registry = object::borrow_mut(registry_obj);
        assert!(!table::contains(&registry.infos, unique_tick), ErrorTickAlreadyExists);
        let mrc20 = MRC20 {
            max: max,
            limit: limit,
            decimals: decimals,
        };
        
        let info = MovescriptionInfo {
            tick: tick,
            protocol: mrc20,
            difficulty: difficulty,
        };
        let info_obj = context::new_object(ctx, info);
        let info_id = object::id(&info_obj);
        object::to_frozen(info_obj);
        let supply = Supply {
            info_id: info_id,
            value: 0,
        };
        table::add(&mut registry.infos, unique_tick, supply);
    }

    entry fun mint_mrc20(ctx: &mut Context, registry_obj: &mut Object<MovescriptionRegistry>, tick: String, value: u256, nonce: u64) {
        let unique_tick = to_lower_case(tick);
        let sender = context::sender(ctx);

        let registry = object::borrow_mut(registry_obj);
        assert!(table::contains(&registry.infos, unique_tick), ErrorTickNotExists);
        let supply = table::borrow_mut(&mut registry.infos, unique_tick);

        let info_obj = context::borrow_object<MovescriptionInfo<MRC20>>(ctx, supply.info_id);
        let info = object::borrow(info_obj);

        assert!(validate_pow(ctx, sender, unique_tick, value, info.difficulty, nonce), ErrorInvalidPoW);
        let mrc20 = &info.protocol;
        assert!(value <= mrc20.limit, ErrorMintExceedsLimit);

        supply.value = supply.value + value;

        assert!(supply.value <= mrc20.max, ErrorMintExceedsMax);
        
        let movescription = Movescription {
            tick: unique_tick,
            value: value,
            metadata: option::none(),
        };
        let movescription_obj = context::new_object(ctx, movescription);
        
        object::transfer(movescription_obj, sender);
    }

    fun to_lower_case(s: String) : String {
        //TODO
        s
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