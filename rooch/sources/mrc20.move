module movescriptions::mrc20{
    use std::string::String;
    use std::option;
    use moveos_std::context::{Self, Context};
    use moveos_std::table::{Self, Table};
    use moveos_std::object::{Self, Object};
    use movescriptions::movescription::{Self, TickInfo, TickRegistry};
    use movescriptions::util;

    const ErrorTickNotFound : u64 = 1;
    const ErrorMintExceedsLimit: u64 = 2;
    const ErrorMintExceedsMax: u64 = 3;

    /// The MRC20 is a protocol like ERC20, BRC20, etc.
    /// The name is not a good name, but we follow the community's convention
    struct MRC20 has key{
        tick_info: Object<TickInfo>,
        /// The total supply of the MRC20
        max: u256,
        /// The limit of per MRC20 mint
        limit: u256,
        /// The decimals of the MRC20
        decimals: u64,
        /// The current supply of the MRC20
        supply: u256,
    }

    struct MRC20Store has key{
        /// The tick to MRC20 Info Object
        ticks: Table<String, Object<MRC20>>,
    }

    fun init(ctx: &mut Context){
        let ticks = context::new_table(ctx);
        let store_obj = context::new_named_object(ctx, MRC20Store{
            ticks,
        });
        object::to_shared(store_obj);
    }

    fun do_deploy(ctx: &mut Context, registry_obj: &mut Object<TickRegistry>, store_obj: &mut Object<MRC20Store>, tick: String, difficulty: u64, max: u256, limit: u256, decimals: u64) {
        let tick_info =  movescription::deploy(ctx, registry_obj, tick, difficulty);
        let mrc20 = MRC20 {
            tick_info: tick_info,
            max: max,
            limit: limit,
            decimals: decimals,
            supply: 0,
        };
        let unique_tick = util::to_lower_case(tick);
        let mrc20_store = object::borrow_mut(store_obj);
        let mrc20_obj = context::new_object(ctx, mrc20);
        table::add(&mut mrc20_store.ticks, unique_tick, mrc20_obj);
    }

    entry fun deploy(ctx: &mut Context, registry_obj: &mut Object<TickRegistry>, store_obj: &mut Object<MRC20Store>, tick: String, difficulty: u64, max: u256, limit: u256, decimals: u64) {
        do_deploy(ctx, registry_obj, store_obj, tick, difficulty, max, limit, decimals);
    }

    fun do_mint(ctx: &mut Context, store_obj: &mut Object<MRC20Store>, tick: String, nonce: u64, value: u256) {
        let sender = context::sender(ctx);
        let unique_tick = util::to_lower_case(tick);
        let mrc20_store = object::borrow_mut(store_obj);
        assert!(table::contains(&mrc20_store.ticks, unique_tick), ErrorTickNotFound);
        let mrc20_obj = table::borrow_mut(&mut mrc20_store.ticks, unique_tick);
        let mrc20 = object::borrow_mut(mrc20_obj);
    
        assert!(value <= mrc20.limit, ErrorMintExceedsLimit);

        mrc20.supply = mrc20.supply + value;

        assert!(mrc20.supply <= mrc20.max, ErrorMintExceedsMax);
        
        let metadata = option::none();
        movescription::mint(ctx, sender, &mrc20.tick_info, nonce, value, metadata);
    } 

    entry fun mint(ctx: &mut Context, store_obj: &mut Object<MRC20Store>, tick: String, nonce: u64, value: u256) {
        do_mint(ctx, store_obj, tick, nonce, value);
    } 



}