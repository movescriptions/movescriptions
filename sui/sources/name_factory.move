module smartinscription::name_factory {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use sui::tx_context::{Self,TxContext};
    use sui::table::{Self,Table};
    use sui::transfer;
    use sui::balance;
    use sui::sui::SUI;
    use sui::coin::{Self,Coin};
    use sui::clock::{Self,Clock};
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2, Movescription, Metadata};
    use smartinscription::tick_name;
    use smartinscription::string_util;
    use smartinscription::content_type;
    use smartinscription::assert_util;
    use smartinscription::util;
    use smartinscription::metadata;

    friend smartinscription::init;

    const TOTAL_SUPPLY: u64 = 0xFFFFFFFFFFFFFFFF; // 18446744073709551615
    const INIT_LOCKED_MOVE: u64 = 1000;
    const BASE_NAME_LENGTH_FEE: u64 = 10;
    const DAY_MS: u64 = 3600000*24;
    const NAME_TIME_FEE_PER_DAY: u64 = 1;

    const ErrorInvaidName: u64 = 1;
    const ErrorNameNotAvailable: u64 = 2;
    
    struct WITNESS has drop{}

    struct NameFactory has store{
        // name -> mint time
        names: Table<String, u64>,
        total_name_fee: Option<Movescription>,
    }

    #[lint_allow(share_owned)]
    /// Deploy the `NAME` tick
    public fun deploy_name_tick(deploy_record: &mut DeployRecord, ctx: &mut TxContext) {
        if(movescription::is_deployed(deploy_record, tick())){
            return
        };
        let name_tick_record = movescription::internal_deploy_with_witness(deploy_record, std::ascii::string(tick()), TOTAL_SUPPLY, false, WITNESS{}, ctx);
        let name_factory = NameFactory{
            names: table::new(ctx),
            total_name_fee: option::none(),
        };
        movescription::tick_record_add_df(&mut name_tick_record, name_factory, WITNESS{});
        transfer::public_share_object(name_tick_record);
    }
    

    #[lint_allow(self_transfer)]
    public entry fun mint(
        name_tick_record: &mut TickRecordV2,
        locked_move: Movescription,
        name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) {
        let ms = do_mint(name_tick_record, locked_move, name, clock, ctx);
        transfer::public_transfer(ms, tx_context::sender(ctx));
    }

    #[lint_allow(self_transfer)]
    public fun do_mint(
        name_tick_record: &mut TickRecordV2,
        locked_move: Movescription,
        name: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext) : Movescription {
        assert_util::assert_tick_record(name_tick_record, tick());
        assert_util::assert_move_tick(&locked_move);
        
        assert!(is_name_valid(name), ErrorInvaidName);
        assert!(is_name_available(name_tick_record, name), ErrorNameNotAvailable);
        
        let init_locked_move = util::split_and_give_back(locked_move, INIT_LOCKED_MOVE, ctx);
        //ensure the name is lowercase
        string_util::to_lowercase(&mut name);
        let name_str = string::utf8(name);
        let name_factory = movescription::tick_record_borrow_mut_df<NameFactory, WITNESS>(name_tick_record, WITNESS{});
        
        let now = clock::timestamp_ms(clock);
        table::add(&mut name_factory.names, name_str, now);
       
        let metadata = new_name_metadata(name_str, now, tx_context::sender(ctx));
        let name_movescription = movescription::do_mint_with_witness(name_tick_record, balance::zero<SUI>(), 1, option::some(metadata), WITNESS{}, ctx);
        movescription::lock_within(&mut name_movescription, init_locked_move);
        name_movescription
    }

    public fun do_burn(name_tick_record: &mut TickRecordV2, movescription: Movescription, clk: &Clock, ctx: &mut TxContext) :(Coin<SUI>, Option<Movescription>) {
        assert_util::assert_tick_record(name_tick_record, tick());
        assert_util::assert_name_tick(&movescription);
        
        let (name, locked_sui, locked_move) = internal_burn(name_tick_record, movescription, clk, ctx);
        //recycle the name when burn.
        let factory = movescription::tick_record_borrow_mut_df<NameFactory, WITNESS>(name_tick_record, WITNESS{});
        table::remove(&mut factory.names, name);
        (locked_sui, locked_move)
    }

    #[lint_allow(self_transfer)]
    public entry fun burn(name_tick_record: &mut TickRecordV2,movescription: Movescription, clk: &Clock, ctx: &mut TxContext){
        let (coin, ms) = do_burn(name_tick_record, movescription, clk, ctx);
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

    fun internal_burn(name_tick_record: &mut TickRecordV2, movescription: Movescription, clk: &Clock, ctx: &mut TxContext) :(String, Coin<SUI>, Option<Movescription>) {
        let (name, timestamp_ms, _miner) = decode_metadata(&movescription);
        let (locked_sui, locked_move) = movescription::do_burn_with_witness(name_tick_record, movescription, *string::bytes(&name), WITNESS{}, ctx); 
        let name_factory = movescription::tick_record_borrow_mut_df<NameFactory, WITNESS>(name_tick_record, WITNESS{});
        let remain = charge_fee(name_factory, name, timestamp_ms, locked_move, clk, ctx);
        (name, locked_sui, remain) 
    }

    fun charge_fee(name_factory: &mut NameFactory, name: String, timestamp_ms: u64, locked_move: Option<Movescription>, clk: &Clock, ctx: &mut TxContext) : Option<Movescription> {
        let now = clock::timestamp_ms(clk);
        let fee = calculate_name_fee(name, timestamp_ms, now);
        if(option::is_some(&locked_move)){
            let locked_move = option::destroy_some(locked_move);
            let (fee_move, remain) = util::split_and_return_remain(locked_move, fee, ctx);
            if(option::is_some(&name_factory.total_name_fee)){
                let total_name_fee = option::borrow_mut(&mut name_factory.total_name_fee);
                movescription::do_merge(total_name_fee, fee_move);
            }else{
                option::fill(&mut name_factory.total_name_fee, fee_move);
            };
            remain
        }else{
            locked_move
        }
    }
    
    fun new_name_metadata(name: String, timestamp_ms: u64, miner: address): Metadata {
        let text_metadata = metadata::new_string_metadata(name, timestamp_ms, miner);
        content_type::new_bcs_metadata(&text_metadata)
    }

    fun decode_metadata(name_movescription: &Movescription) : (String, u64, address) {
        let metadata = movescription::metadata(name_movescription);
        let metadata = option::destroy_some(metadata);
        let text_metadata = metadata::decode_text_metadata(&metadata);
        let (text, timestamp_ms, miner) = metadata::unpack_text_metadata(text_metadata);
        (string::utf8(text), timestamp_ms, miner)
    }

    public fun tick() : vector<u8> {
        tick_name::name_tick()
    }
    
    /// Check if the name is available, if it has bean minted, it is not available
    public fun is_name_available(name_tick_record: &TickRecordV2, name: vector<u8>) : bool {
        string_util::to_lowercase(&mut name);
        let name_str = string::utf8(name);
        let name_factory = movescription::tick_record_borrow_df<NameFactory>(name_tick_record);
        !table::contains(&name_factory.names, name_str)
    }

    /// Check if the name is valid
    /// We currently reuse the tick name validation, but we may have different validation rules in the future
    /// We save the utf8 string in the table, but we require the ascii string here, in the future, we may support utf8 string
    public fun is_name_valid(name: vector<u8>) : bool {
        tick_name::is_tick_name_valid(name)
    }

    // ====== Name factory functions ======

    public fun names(name_tick_record: &TickRecordV2) : &Table<String, u64> {
        let name_factory = movescription::tick_record_borrow_df<NameFactory>(name_tick_record);
        &name_factory.names
    }

    public fun total_name_fee(name_tick_record: &TickRecordV2) : u64 {
        let name_factory = movescription::tick_record_borrow_df<NameFactory>(name_tick_record);
        if(option::is_none(&name_factory.total_name_fee)){
            0
        }else{
            let ms = option::borrow(&name_factory.total_name_fee);
            movescription::amount(ms)
        }
    }

    // ===== Constants functions =====
        
    public fun init_locked_move() : u64 {
        INIT_LOCKED_MOVE
    }

    public fun calculate_name_fee(name: String, mint_time: u64, now: u64): u64 {
        let name_len: u64 = string::length(&name);
        let name_len_fee =  BASE_NAME_LENGTH_FEE * tick_name::min_tick_length()/name_len;
        let time_fee = (now - mint_time)/DAY_MS * NAME_TIME_FEE_PER_DAY;
        let fee = name_len_fee + time_fee;
        if(fee > INIT_LOCKED_MOVE){
            INIT_LOCKED_MOVE
        }else{
            fee
        }
    }

    // ======== Test functions ========

    #[test]
    fun test_calculate_name_fee(){
        let fee = calculate_name_fee(string::utf8(b"abcd"), 0, 0);
        assert!(fee == 10, 0);
        let fee = calculate_name_fee(string::utf8(b"abcde"), 0, 0);
        assert!(fee == 8, 0);
        let fee = calculate_name_fee(string::utf8(b"ab123456789012345678901234567890"), 0, 0);
        assert!(fee == 1, 0);
        let fee = calculate_name_fee(string::utf8(b"abcd"), 0, DAY_MS*365*2);
        assert!(fee == 740, 0);
        let fee = calculate_name_fee(string::utf8(b"abcd"), 0, DAY_MS*365*10);
        assert!(fee == INIT_LOCKED_MOVE, 0);
    }
}