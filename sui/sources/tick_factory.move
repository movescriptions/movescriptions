module smartinscription::tick_factory {
    use std::ascii::{Self, String};
    use std::option::{Self, Option};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::balance;
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2, Movescription, Metadata};
    use smartinscription::content_type;
    use smartinscription::string_util;
    use smartinscription::assert_util;
    use smartinscription::tick_name::{Self, is_tick_name_valid, is_tick_name_reserved};
    use smartinscription::util;
    use smartinscription::metadata;

    const TOTAL_SUPPLY: u64 = 0xFFFFFFFFFFFFFFFF; // 18446744073709551615
    const INIT_LOCKED_MOVE: u64 = 10000;
    const BASE_TICK_LENGTH_FEE: u64 = 1000;
    const HOUR_MS: u64 = 3600000;
    const TICK_TIME_FEE_PER_HOUR: u64 = 1;

    const ErrorInvaidTickName: u64 = 1;
    const ErrorTickNameNotAvailable: u64 = 2;

    struct WITNESS has drop{}
    
    struct TickFactory has store{
        /// Tick name -> tick mint time
        tick_names: Table<String, u64>,
        /// The total tick fee, it is MOVE movescription.
        total_tick_fee: Option<Movescription>,
    }
    
    #[lint_allow(share_owned)]
    /// Deploy the `TICK` movescription
    public fun deploy_tick_tick(deploy_record: &mut DeployRecord, ctx: &mut TxContext) {
        if(movescription::is_deployed(deploy_record, tick())){
            return
        };
        let tick_tick_record = movescription::internal_deploy_with_witness(deploy_record, ascii::string(tick()), TOTAL_SUPPLY, false, WITNESS{}, ctx);
        let tick_factory = TickFactory{
            tick_names: table::new(ctx),
            total_tick_fee: option::none(),
        };
        movescription::tick_record_add_df(&mut tick_tick_record, tick_factory, WITNESS{});
        transfer::public_share_object(tick_tick_record);
    }

     #[lint_allow(self_transfer)]
    public fun do_deploy<W: drop>(
        deploy_record: &mut DeployRecord, 
        tick_tick_record: &mut TickRecordV2,
        tick_name_movescription: Movescription,
        total_supply: u64,
        burnable: bool,
        _witness: W,
        clk: &Clock,
        ctx: &mut TxContext
    ) : TickRecordV2 {
        assert_util::assert_tick_record(tick_tick_record, tick());
        assert_util::assert_tick_tick(&tick_name_movescription);
        
        let (tick_name, coin, locked_move) = internal_burn(tick_tick_record, tick_name_movescription, clk, ctx);
        
        let new_tick_record = movescription::internal_deploy_with_witness(deploy_record, tick_name, total_supply, burnable, _witness, ctx);
        
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(coin, sender);
        if(option::is_some(&locked_move)){
            let locked_move = option::destroy_some(locked_move);
            transfer::public_transfer(locked_move, sender)
        }else{
            option::destroy_none(locked_move);
        };
        new_tick_record
    }

    #[lint_allow(self_transfer)]
    public fun do_mint(
        tick_tick_record: &mut TickRecordV2,
        locked_move: Movescription,
        tick_name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) : Movescription {
        assert_util::assert_tick_record(tick_tick_record, tick());
        assert_util::assert_move_tick(&locked_move);
        
        assert!(is_tick_name_valid(tick_name), ErrorInvaidTickName);
        assert!(is_tick_name_available(tick_tick_record, tick_name), ErrorTickNameNotAvailable);
        
        let sender = tx_context::sender(ctx);
        let init_locked_move = util::split_and_give_back(locked_move, INIT_LOCKED_MOVE, ctx);
    
        string_util::to_uppercase(&mut tick_name);
        let tick_name_str = ascii::string(tick_name);
        
        let tick_factory = movescription::tick_record_borrow_mut_df<TickFactory, WITNESS>(tick_tick_record, WITNESS{});
        let now = clock::timestamp_ms(clock);
        table::add(&mut tick_factory.tick_names, tick_name_str, now);
       
        let metadata = new_tick_metadata(tick_name_str, now, sender);
        let tick_name_movescription = movescription::do_mint_with_witness(tick_tick_record, balance::zero<SUI>(), 1, option::some(metadata), WITNESS{}, ctx);
        movescription::lock_within(&mut tick_name_movescription, init_locked_move);
        tick_name_movescription
    }

     #[lint_allow(self_transfer)]
    public entry fun mint(
        tick_tick_record: &mut TickRecordV2,
        locked_move: Movescription,
        tick_name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) {
        let ms = do_mint(tick_tick_record, locked_move, tick_name, clock, ctx);
        transfer::public_transfer(ms, tx_context::sender(ctx));
    }


    public fun do_burn(tick_tick_record: &mut TickRecordV2, movescription: Movescription, clk: &Clock, ctx: &mut TxContext) :(Coin<SUI>, Option<Movescription>) {
        assert_util::assert_tick_record(tick_tick_record, tick());
        assert_util::assert_tick_tick(&movescription);
        let (tick_name, locked_sui, locked_move) = internal_burn(tick_tick_record, movescription, clk, ctx);
        // recycle the tick name when burn.
        let tick_factory = movescription::tick_record_borrow_mut_df<TickFactory, WITNESS>(tick_tick_record, WITNESS{});
        table::remove(&mut tick_factory.tick_names, tick_name);
        (locked_sui, locked_move) 
    }

    #[lint_allow(self_transfer)]
    public entry fun burn(tick_tick_record: &mut TickRecordV2,movescription: Movescription, clk: &Clock, ctx: &mut TxContext){
        let (coin, ms) = do_burn(tick_tick_record, movescription, clk, ctx);
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
    public fun is_tick_name_available(tick_tick_record: &TickRecordV2, tick_name: vector<u8>) : bool {
        string_util::to_uppercase(&mut tick_name);
        let tick_name_str = ascii::string(tick_name);
        let tick_factory = movescription::tick_record_borrow_df<TickFactory>(tick_tick_record);
        !table::contains(&tick_factory.tick_names, tick_name_str) && !is_tick_name_reserved(ascii::into_bytes(tick_name_str))
    }

    fun new_tick_metadata(tick_name: String, timestamp_ms: u64, miner: address): Metadata {
        let text_metadata = metadata::new_ascii_metadata(tick_name, timestamp_ms, miner);
        content_type::new_bcs_metadata(&text_metadata)
    }

    fun decode_metadata(tick_name_movescription: &Movescription) : (String, u64, address) {
        let metadata = movescription::metadata(tick_name_movescription);
        let metadata = option::destroy_some(metadata);
        let text_metadata = metadata::decode_text_metadata(&metadata);
        let (text, timestamp_ms, miner) = metadata::unpack_text_metadata(text_metadata);
        (ascii::string(text), timestamp_ms, miner)
    }

    fun internal_burn(tick_tick_record: &mut TickRecordV2, movescription: Movescription, clk: &Clock, ctx: &mut TxContext) :(String, Coin<SUI>, Option<Movescription>) {
        let (tick_name, timestamp_ms, _miner) = decode_metadata(&movescription);
        let (locked_sui, locked_move) = movescription::do_burn_with_witness(tick_tick_record, movescription, ascii::into_bytes(tick_name), WITNESS{}, ctx); 
        let tick_factory = movescription::tick_record_borrow_mut_df<TickFactory, WITNESS>(tick_tick_record, WITNESS{});
        let remain = charge_fee(tick_factory, tick_name, timestamp_ms, locked_move, clk, ctx);
        (tick_name, locked_sui, remain) 
    }

    fun charge_fee(tick_factory: &mut TickFactory, tick_name: String, timestamp_ms: u64, locked_move: Option<Movescription>, clk: &Clock, ctx: &mut TxContext) : Option<Movescription> {
        let now = clock::timestamp_ms(clk);
        let fee = calculate_tick_fee(tick_name, timestamp_ms, now);
        if(option::is_some(&locked_move)){
            let locked_move = option::destroy_some(locked_move);
            let (fee_move, remain) = util::split_and_return_remain(locked_move, fee, ctx);
            if(option::is_some(&tick_factory.total_tick_fee)){
                let total_tick_fee = option::borrow_mut(&mut tick_factory.total_tick_fee);
                movescription::do_merge(total_tick_fee, fee_move);
            }else{
                option::fill(&mut tick_factory.total_tick_fee, fee_move);
            };
            remain
        }else{
            locked_move
        }
    }

    // ===== TickFactory functions =====

    public fun tick_names(tick_tick_record: &TickRecordV2) : &Table<String, u64> {
        let tick_factory = movescription::tick_record_borrow_df<TickFactory>(tick_tick_record);
        &tick_factory.tick_names
    }

    public fun total_tick_fee(tick_tick_record: &TickRecordV2) : u64 {
        let tick_factory = movescription::tick_record_borrow_df<TickFactory>(tick_tick_record);
        if(option::is_none(&tick_factory.total_tick_fee)){
            0
        }else{
            let ms = option::borrow(&tick_factory.total_tick_fee);
            movescription::amount(ms)
        }
    }

    // ===== Constants functions =====

    public fun tick() : vector<u8> {
        tick_name::tick_tick()
    }
    
    public fun init_locked_move() : u64 {
        INIT_LOCKED_MOVE
    }

    public fun calculate_tick_fee(tick: String, mint_time: u64, now: u64): u64 {
        let tick_len: u64 = ascii::length(&tick);
        let tick_len_fee =  BASE_TICK_LENGTH_FEE * tick_name::min_tick_length()/tick_len;
        let time_fee = (now - mint_time)/HOUR_MS * TICK_TIME_FEE_PER_HOUR;
        let fee = tick_len_fee + time_fee;
        if(fee > INIT_LOCKED_MOVE){
            INIT_LOCKED_MOVE
        }else{
            fee
        }
    }

    // ===== Test functions =====
    #[test_only]
    public fun new_tick_movescription_for_testing(tick: String, timestamp_ms: u64, ctx: &mut TxContext) : Movescription{
        let metadata = new_tick_metadata(tick, timestamp_ms, tx_context::sender(ctx));
        movescription::new_movescription_for_testing(1, ascii::string(tick()), sui::balance::zero<SUI>(), option::some(metadata), ctx)
    }

    #[test]
    fun test_calculate_tick_fee(){
        let fee = calculate_tick_fee(ascii::string(b"MOVE"), 0, 0);
        assert!(fee == 1000, 0);
        let fee = calculate_tick_fee(ascii::string(b"MOVER"), 0, 0);
        assert!(fee == 800, 0);
        let fee = calculate_tick_fee(ascii::string(b"MMMMMMMMMMMMMMMMMMMMMMMMMMMMOVER"), 0, 0);
        assert!(fee == 125, 0);
        let fee = calculate_tick_fee(ascii::string(b"MOVE"), 0, HOUR_MS*24*365);
        assert!(fee == 9760, 0);
        let fee = calculate_tick_fee(ascii::string(b"MOVE"), 0, HOUR_MS*24*365*2);
        assert!(fee == INIT_LOCKED_MOVE, 0);
    }
}