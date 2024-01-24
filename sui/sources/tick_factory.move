module smartinscription::tick_factory {
    use std::ascii::{Self, String};
    use std::option;
    use sui::coin::Coin;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2, Movescription};
    use smartinscription::content_type;
    use smartinscription::string_util;
    use smartinscription::tick_name::{is_tick_name_valid, is_tick_name_reserved};

    const TICK: vector<u8> = b"TICK";
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
    public fun deploy(deploy_record: &mut DeployRecord, ctx: &mut TxContext) {
        assert!(!movescription::is_deployed(deploy_record, TICK), ErrorAlreadyDeployed);
        let tick_record = movescription::internal_deploy_with_witness(deploy_record, ascii::string(TICK), TOTAL_SUPPLY, INIT_LOCKED_SUI, WITNESS{}, ctx);
        let tick_factory = TickFactory{
            tick_names: table::new(ctx),
        };
        //TODO migrate the deployed tick names to the new tick factory
        movescription::tick_record_add_df(&mut tick_record, tick_factory, WITNESS{});
        transfer::public_share_object(tick_record);
    }

    public fun do_mint(
        tick_record: &mut TickRecordV2,
        init_locked_coin: Coin<SUI>,
        tick_name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) : Movescription {
        assert!(movescription::check_tick_record(tick_record, TICK), ErrorInvalidTickRecord);
        assert!(is_tick_name_valid(tick_name), ErrorInvaidTickName);
        assert!(is_tick_name_available(tick_record, tick_name), ErrorTickNameNotAvailable);

        let now = clock::timestamp_ms(clock);
        let tick_name_str = ascii::string(tick_name);
        let tick_factory = movescription::tick_record_borrow_mut_df<TickFactory, WITNESS>(tick_record, WITNESS{});
        table::add(&mut tick_factory.tick_names, tick_name_str, now);
        //TODO record mint time to the metadata
        let metadata = content_type::new_ascii_metadata(&tick_name_str);
        movescription::do_mint_with_witness(tick_record, init_locked_coin, 1, option::some(metadata), WITNESS{}, ctx)
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
        TICK
    }
    
    public fun init_locked_sui() : u64 {
        INIT_LOCKED_SUI
    }


}