module smartinscription::tick_factory {
    use std::ascii::{Self, String};
    use std::option;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2, Movescription, Metadata};
    use smartinscription::content_type;
    use smartinscription::string_util;
    use smartinscription::tick_name::{Self, is_tick_name_valid, is_tick_name_reserved};

    const TOTAL_SUPPLY: u64 = 0xFFFFFFFFFFFFFFFF; // 18446744073709551615
    const INIT_LOCKED_SUI: u64 = 10_000000000; // 10 SUI

    const ErrorInvalidTickRecord: u64 = 1;
    const ErrorInvaidTickName: u64 = 2;
    const ErrorTickNameNotAvailable: u64 = 3;
    const ErrorAlreadyDeployed: u64 = 4;

    struct WITNESS has drop{}
    
    struct TickFactory has store{
        // Tick name -> tick mint time
        tick_names: Table<String, u64>,
    }

    
    #[lint_allow(share_owned)]
    /// Deploy the `TICK` movescription
    public fun do_deploy(deploy_record: &mut DeployRecord, ctx: &mut TxContext) {
        assert!(!movescription::is_deployed(deploy_record, tick()), ErrorAlreadyDeployed);
        let tick_record = movescription::internal_deploy_with_witness(deploy_record, ascii::string(tick()), TOTAL_SUPPLY, WITNESS{}, ctx);
        let tick_factory = TickFactory{
            tick_names: table::new(ctx),
        };
        //TODO migrate the deployed tick names to the new tick factory
        movescription::tick_record_add_df(&mut tick_record, tick_factory, WITNESS{});
        transfer::public_share_object(tick_record);
    }

    public entry fun deploy(deploy_record: &mut DeployRecord, ctx: &mut TxContext) {
        do_deploy(deploy_record, ctx);
    }

    #[lint_allow(self_transfer)]
    public fun do_mint(
        tick_record: &mut TickRecordV2,
        init_locked_coin: Coin<SUI>,
        tick_name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) : Movescription {
        assert!(movescription::check_tick_record(tick_record, tick_name::protocol_tick_name_tick()), ErrorInvalidTickRecord);
        assert!(is_tick_name_valid(tick_name), ErrorInvaidTickName);
        assert!(is_tick_name_available(tick_record, tick_name), ErrorTickNameNotAvailable);
        let sender = tx_context::sender(ctx);
        let acc_coin = if(coin::value<SUI>(&init_locked_coin) == INIT_LOCKED_SUI){
            init_locked_coin
        }else{
            let acc_coin = coin::split<SUI>(&mut init_locked_coin, INIT_LOCKED_SUI, ctx);
            transfer::public_transfer(init_locked_coin, sender);
            acc_coin
        };
        let init_locked_balance = coin::into_balance<SUI>(acc_coin);

        let now = clock::timestamp_ms(clock);
        let tick_name_str = ascii::string(tick_name);
        let tick_factory = movescription::tick_record_borrow_mut_df<TickFactory, WITNESS>(tick_record, WITNESS{});
        table::add(&mut tick_factory.tick_names, tick_name_str, now);
       
        let metadata = new_tick_metadata(tick_name_str, now);
        movescription::do_mint_with_witness(tick_record, init_locked_balance, 1, option::some(metadata), WITNESS{}, ctx)
    }

    public fun new_tick_metadata(tick: String, _timestamp_ms: u64): Metadata {
         //TODO record mint time to the metadata
         content_type::new_ascii_metadata(&tick)
    }

    #[lint_allow(self_transfer)]
    public entry fun mint(
        tick_record: &mut TickRecordV2,
        init_locked_coin: Coin<SUI>,
        tick_name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) {
        let ms = do_mint(tick_record, init_locked_coin, tick_name, clock, ctx);
        transfer::public_transfer(ms, tx_context::sender(ctx));
    }

    /// Check if the tick name is available, if it has bean minted or deployed or reserved, it is not available
    public fun is_tick_name_available(tick_record: &mut TickRecordV2, tick_name: vector<u8>) : bool {
        string_util::to_uppercase(&mut tick_name);
        let tick_name_str = ascii::string(tick_name);
        let tick_factory = movescription::tick_record_borrow_df<TickFactory>(tick_record);
        !table::contains(&tick_factory.tick_names, tick_name_str) && !is_tick_name_reserved(ascii::into_bytes(tick_name_str))
    }

    // ===== Constants functions =====

    public fun tick() : vector<u8> {
        tick_name::protocol_tick_name_tick()
    }
    
    public fun init_locked_sui() : u64 {
        INIT_LOCKED_SUI
    }

    // ===== Test functions =====
    #[test_only]
    public fun new_tick_movescription_for_testing(tick: String, timestamp_ms: u64, ctx: &mut TxContext) : Movescription{
        let metadata = new_tick_metadata(tick, timestamp_ms);
        movescription::new_movescription_for_testing(1, ascii::string(tick()), sui::balance::zero<SUI>(), option::some(metadata), ctx)
    }
}