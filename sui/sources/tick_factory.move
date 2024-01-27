module smartinscription::tick_factory {
    use std::ascii::{Self, String};
    use std::option::{Self, Option};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::bcs;
    use sui::balance;
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2, Movescription, Metadata};
    use smartinscription::content_type;
    use smartinscription::string_util;
    use smartinscription::assert_util;
    use smartinscription::tick_name::{Self, is_tick_name_valid, is_tick_name_reserved};
    use smartinscription::util;

    const TOTAL_SUPPLY: u64 = 0xFFFFFFFFFFFFFFFF; // 18446744073709551615
    const INIT_LOCKED_MOVE: u64 = 10000;

    const ErrorInvalidTickRecord: u64 = 1;
    const ErrorInvaidTickName: u64 = 2;
    const ErrorTickNameNotAvailable: u64 = 3;
    const ErrorInvalidMetadata: u64 = 4;

    struct WITNESS has drop{}
    
    struct TickFactory has store{
        // Tick name -> tick mint time
        tick_names: Table<String, u64>,
    }

    struct TickNameMetadta has store, copy, drop {
        tick_name: String,
        timestamp_ms: u64,
        miner: address,
    }
    
    #[lint_allow(share_owned)]
    /// Deploy the `TICK` movescription
    public fun deploy_tick_tick(deploy_record: &mut DeployRecord, ctx: &mut TxContext) {
        if(movescription::is_deployed(deploy_record, tick())){
            return
        };
        let tick_record = movescription::internal_deploy_with_witness(deploy_record, ascii::string(tick()), TOTAL_SUPPLY, false, WITNESS{}, ctx);
        let tick_factory = TickFactory{
            tick_names: table::new(ctx),
        };
        //TODO migrate the deployed tick names to the new tick factory
        movescription::tick_record_add_df(&mut tick_record, tick_factory, WITNESS{});
        transfer::public_share_object(tick_record);
    }

     #[lint_allow(self_transfer)]
    public fun do_deploy<W: drop>(
        deploy_record: &mut DeployRecord, 
        tick_tick_record: &mut TickRecordV2,
        tick_name_movescription: Movescription,
        total_supply: u64,
        burnable: bool,
        _witness: W,
        ctx: &mut TxContext
    ) : TickRecordV2 {
        assert_util::assert_tick_tick(&tick_name_movescription);
        let tick_name_metadata = decode_metadata(&tick_name_movescription);
        let new_tick_record = movescription::internal_deploy_with_witness(deploy_record, tick_name_metadata.tick_name, total_supply, burnable, _witness, ctx);
        let (coin, locked_movescription) = internal_burn(tick_tick_record, tick_name_movescription, tick_name_metadata.tick_name, ctx);
        //TODO charge deploy fee
        transfer::public_transfer(coin, tx_context::sender(ctx));
        if(option::is_some(&locked_movescription)){
            transfer::public_transfer(option::destroy_some(locked_movescription), tx_context::sender(ctx));
        }else{
            option::destroy_none(locked_movescription);
        };
        new_tick_record
    }

    #[lint_allow(self_transfer)]
    public fun do_mint(
        tick_record: &mut TickRecordV2,
        locked_move: Movescription,
        tick_name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) : Movescription {
        assert!(movescription::check_tick_record(tick_record, tick_name::tick_tick()), ErrorInvalidTickRecord);
        assert_util::assert_move_tick(&locked_move);
        assert!(is_tick_name_valid(tick_name), ErrorInvaidTickName);
        assert!(is_tick_name_available(tick_record, tick_name), ErrorTickNameNotAvailable);
        let sender = tx_context::sender(ctx);
        let init_locked_move = util::split_and_give_back(locked_move, INIT_LOCKED_MOVE, ctx);
    

        let now = clock::timestamp_ms(clock);
        let tick_name_str = ascii::string(tick_name);
        let tick_factory = movescription::tick_record_borrow_mut_df<TickFactory, WITNESS>(tick_record, WITNESS{});
        table::add(&mut tick_factory.tick_names, tick_name_str, now);
       
        let metadata = new_tick_metadata(tick_name_str, now, sender);
        let tick_name_movescription = movescription::do_mint_with_witness(tick_record, balance::zero<SUI>(), 1, option::some(metadata), WITNESS{}, ctx);
        movescription::lock_within(&mut tick_name_movescription, init_locked_move);
        tick_name_movescription
    }

     #[lint_allow(self_transfer)]
    public entry fun mint(
        tick_record: &mut TickRecordV2,
        locked_move: Movescription,
        tick_name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) {
        let ms = do_mint(tick_record, locked_move, tick_name, clock, ctx);
        transfer::public_transfer(ms, tx_context::sender(ctx));
    }

    public fun new_tick_metadata(tick_name: String, timestamp_ms: u64, miner: address): Metadata {
        let tick_name_metadata = TickNameMetadta{
            tick_name: tick_name,
            timestamp_ms: timestamp_ms,
            miner: miner,
        };
         content_type::new_bcs_metadata(&tick_name_metadata)
    }

    public fun decode_metadata(tick_name_movescription: &Movescription) : TickNameMetadta {
        assert_util::assert_tick_tick(tick_name_movescription);
        let metadata = movescription::metadata(tick_name_movescription);
        let metadata = option::destroy_some(metadata);
        let (ct, content) = movescription::unpack_metadata(metadata);
        assert!(content_type::is_bcs(&ct), ErrorInvalidMetadata);
        let bcs = bcs::new(content);
        let tick_name = ascii::string(bcs::peel_vec_u8(&mut bcs));
        let timestamp_ms = bcs::peel_u64(&mut bcs);
        let miner = bcs::peel_address(&mut bcs);
        TickNameMetadta{
            tick_name,
            timestamp_ms,
            miner
        }
    }

    fun internal_burn(tick_record: &mut TickRecordV2, movescription: Movescription, tick_name: String, ctx: &mut TxContext) :(Coin<SUI>, Option<Movescription>) {
        movescription::do_burn_with_witness(tick_record, movescription, ascii::into_bytes(tick_name), WITNESS{}, ctx)
    }

    public fun do_burn(tick_record: &mut TickRecordV2, movescription: Movescription, ctx: &mut TxContext) :(Coin<SUI>, Option<Movescription>) {
        assert!(movescription::check_tick_record(tick_record, tick()), ErrorInvalidTickRecord);
        assert_util::assert_tick_tick(&movescription);
        let metadata = decode_metadata(&movescription);
        // recycle the tick name when burn.
        let tick_factory = movescription::tick_record_borrow_mut_df<TickFactory, WITNESS>(tick_record, WITNESS{});
        table::remove(&mut tick_factory.tick_names, metadata.tick_name);
        internal_burn(tick_record, movescription, metadata.tick_name, ctx)
    }

    #[lint_allow(self_transfer)]
    public entry fun burn(tick_record: &mut TickRecordV2,movescription: Movescription, ctx: &mut TxContext){
        let (coin, ms) = do_burn(tick_record, movescription, ctx);
        if(coin::value(&coin) == 0){
            coin::destroy_zero(coin);
        }else{
            transfer::public_transfer(coin, tx_context::sender(ctx));
        };
        if(option::is_some(&ms)){
            transfer::public_transfer(option::destroy_some(ms), tx_context::sender(ctx));
        }else{
            option::destroy_none(ms);
        };
    }

    /// Check if the tick name is available, if it has bean minted or deployed or reserved, it is not available
    public fun is_tick_name_available(tick_record: &mut TickRecordV2, tick_name: vector<u8>) : bool {
        string_util::to_uppercase(&mut tick_name);
        let tick_name_str = ascii::string(tick_name);
        let tick_factory = movescription::tick_record_borrow_df<TickFactory>(tick_record);
        !table::contains(&tick_factory.tick_names, tick_name_str) && !is_tick_name_reserved(ascii::into_bytes(tick_name_str))
    }

    // ===== TickNameMetadta functions =====

    public fun metadata_tick_name(tick_name_metadata: &TickNameMetadta) : String {
        tick_name_metadata.tick_name
    }

    public fun metadata_timestamp_ms(tick_name_metadata: &TickNameMetadta) : u64 {
        tick_name_metadata.timestamp_ms
    }

    public fun metadata_miner(tick_name_metadata: &TickNameMetadta) : address {
        tick_name_metadata.miner
    }

    // ===== Constants functions =====

    public fun tick() : vector<u8> {
        tick_name::tick_tick()
    }
    
    public fun init_locked_move() : u64 {
        INIT_LOCKED_MOVE
    }

    // ===== Test functions =====
    #[test_only]
    public fun new_tick_movescription_for_testing(tick: String, timestamp_ms: u64, ctx: &mut TxContext) : Movescription{
        let metadata = new_tick_metadata(tick, timestamp_ms, tx_context::sender(ctx));
        movescription::new_movescription_for_testing(1, ascii::string(tick()), sui::balance::zero<SUI>(), option::some(metadata), ctx)
    }
}