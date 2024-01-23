module smartinscription::tick_factory {
    use std::ascii::{Self, String};
    use std::vector;
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

    const TICK: vector<u8> = b"TICK";
    const TOTAL_SUPPLY: u64 = 0xFFFFFFFFFFFFFFFF; // 18446744073709551615
    const INIT_LOCKED_SUI: u64 = 10_000000000; // 10 SUI
    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;
    const DISALLOWED_TICK_CHARS: vector<u8> = b" .\"'\\/<>?;:[]{}()!@#$%^&*+=|~-,`";

    const ErrorInvalidTickRecord: u64 = 1;
    const ErrorInvaidTickName: u64 = 2;
    const ErrorTickNameNotAvailable: u64 = 3;

    struct WITNESS has drop{}
    
    struct TickFactory has store{
        // Tick name -> tick mint time
        tick_names: Table<String, u64>,
    }

    #[lint_allow(share_owned)]
    public fun deploy(deploy_record: &mut DeployRecord, ctx: &mut TxContext) {
        let tick_record = movescription::do_deploy_with_witness(deploy_record, ascii::string(TICK), TOTAL_SUPPLY, INIT_LOCKED_SUI, WITNESS{}, ctx);
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

    public fun is_tick_name_reserved(tick_name: vector<u8>) : bool {
        string_util::to_uppercase(&mut tick_name);
        tick_name == b"TICK" || tick_name == b"NAME"
    }

    /// Check if the tick name is valid
    public fun is_tick_name_valid(tick_name: vector<u8>) : bool {
        let tick_len = vector::length(&tick_name);
        if(tick_len < MIN_TICK_LENGTH || tick_len > MAX_TICK_LENGTH) {
            return false
        };
        if (string_util::contains_any(&tick_name, &DISALLOWED_TICK_CHARS)){
            return false
        };
        let str_opt = ascii::try_string(tick_name);
        if(option::is_none(&str_opt)) {
            return false
        };
        let tick_name = option::destroy_some(str_opt);
        ascii::all_characters_printable(&tick_name)
    }

    // ===== Constants functions =====

    public fun tick() : vector<u8> {
        TICK
    }
    
    public fun init_locked_sui() : u64 {
        INIT_LOCKED_SUI
    }

    #[test]
    fun test_is_tick_name_valid() {
        assert!(!is_tick_name_valid(b"abc"), 1);
        assert!(!is_tick_name_valid(b"123456789012345678901234567890123"), 1);
        assert!(is_tick_name_valid(b"abcd"), 2);
        assert!(is_tick_name_valid(b"ab_d"), 2);
        assert!(!is_tick_name_valid(b"abc!"), 3);
        assert!(!is_tick_name_valid(b"abc "), 4);
        assert!(!is_tick_name_valid(b"abc."), 5);
        assert!(!is_tick_name_valid(b"abc@"), 6);
        assert!(!is_tick_name_valid(b"abc#"), 7);
        assert!(!is_tick_name_valid(b"abc$"), 8);
        assert!(!is_tick_name_valid(b"abc&"), 9);
        assert!(!is_tick_name_valid(b"abc="), 10);
        assert!(!is_tick_name_valid(b"abc+"), 11);
        assert!(!is_tick_name_valid(b"abc-"), 12);
        assert!(!is_tick_name_valid(b"abc*"), 13);
        assert!(!is_tick_name_valid(b"abc/"), 14);
        assert!(!is_tick_name_valid(b"abc\\"), 15);
        assert!(!is_tick_name_valid(b"abc|"), 16);
        assert!(!is_tick_name_valid(b"abc<"), 17);
        assert!(!is_tick_name_valid(b"abc>"), 18);
        assert!(!is_tick_name_valid(b"abc,"), 19);
        assert!(!is_tick_name_valid(b"abc?"), 20);
        assert!(!is_tick_name_valid(b"abc;"), 21);
        assert!(!is_tick_name_valid(b"abc:"), 22);
        assert!(!is_tick_name_valid(b"abc["), 23);
        assert!(!is_tick_name_valid(b"abc]"), 24);
        assert!(!is_tick_name_valid(b"abc{"), 25);
        assert!(!is_tick_name_valid(b"abc}"), 26);
        assert!(!is_tick_name_valid(b"abc("), 27);
        assert!(!is_tick_name_valid(b"abc)"), 28);
        assert!(!is_tick_name_valid(b"abc'"), 29);
        assert!(!is_tick_name_valid(b"abc\""), 30);
        assert!(!is_tick_name_valid(b"abc`"), 31);
        assert!(!is_tick_name_valid(b"abc~"), 32);
    }
}