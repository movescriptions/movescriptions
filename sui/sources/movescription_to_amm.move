module smartinscription::movescription_to_amm{
    use std::option;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::Clock;
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::math;
    use sui::package::{Publisher};
    use cetus_clmm::factory::{Self, Pools};
    use cetus_clmm::pool::{Self, Pool};
    use cetus_clmm::position::{Self, Position};
    use cetus_clmm::config::{GlobalConfig};
    use cetus_clmm::tick_math;
    use cetus_clmm::clmm_math;
    use cetus_clmm::rewarder::{Self, RewarderGlobalVault};
    use integer_mate::i32::{Self, I32};
    use smartinscription::movescription::{Self, Movescription, TickRecordV2};

    const CETUS_TICK_SPACING: u32 = 200;
    const SUI_DECIMALS: u8 = 9;
    const CETUS_MIN_TICK_U32: u32 = 4294523696; // see test_check_postion_tick_range
    const CETUS_MAX_TICK_U32: u32 = 443600; // see test_check_postion_tick_range
    const ReferenceFeeRewardPercent: u64 = 1;

    const ErrorTreasuryNotInited: u64 = 1;
    const ErrorCoinTypeMissMatch: u64 = 2;
    const ErrorNotSupported: u64 = 3;
    const ErrorPoolNotInited: u64 = 4;
    const ErrorPoolAlreadyInited: u64 = 5;
    const ErrorNoLiquidity: u64 = 6;
    const ErrorInvalidInitLiquidity: u64 = 7;
    const ErrorInvalidState: u64 = 8;
    const ErrorInvalidCap: u64 = 9;

    struct Positions has store{
        positions: Table<address, Position>,
    }

    /// Initialize a pool with liquidity
    public entry fun init_pool<T: drop>(
        pools: &mut Pools, 
        config: &GlobalConfig, 
        tick_record: &mut TickRecordV2, 
        movescription: Movescription, 
        clk: &Clock, 
        ctx: &mut TxContext
    ) {
        assert!(movescription::is_treasury_inited(tick_record), ErrorTreasuryNotInited);
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(!movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolAlreadyInited);

        let (balance_a, balance_b) = movescription_to_lpt<T>(tick_record, movescription);
        let amount_a = balance::value(&balance_a);
        let amount_b = balance::value(&balance_b);
        assert!(amount_a > 0, ErrorInvalidInitLiquidity);
        assert!(amount_b > 0, ErrorInvalidInitLiquidity);
        let decimals_a = movescription::mcoin_decimals();
        let decimals_b = SUI_DECIMALS;
        let initialize_price = price_to_sqrt_price_x64(amount_a, amount_b, decimals_a, decimals_b);

        let (position, coin_a, coin_b) = factory::create_pool_with_liquidity<T,SUI>(
            pools, config, CETUS_TICK_SPACING, initialize_price, std::string::utf8(b""), 
            CETUS_MIN_TICK_U32,
            CETUS_MAX_TICK_U32,
            coin::from_balance(balance_a, ctx),
            coin::from_balance(balance_b, ctx),
            amount_a,
            amount_b,
            true,
            clk, 
            ctx);
        let positions = Positions{positions: table::new(ctx)};
        let sender = tx_context::sender(ctx);
        table::add(&mut positions.positions, sender, position);
        movescription::tick_record_add_df_internal(tick_record, positions);
        if(coin::value(&coin_a) > 0){
            transfer::public_transfer(coin_a, tx_context::sender(ctx));
        }else{
            coin::destroy_zero(coin_a);
        };
        if(coin::value(&coin_b) > 0){
            transfer::public_transfer(coin_b, tx_context::sender(ctx));
        }else{
            coin::destroy_zero(coin_b);
        };
    }

    public entry fun add_liquidity<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        movescription: Movescription, 
        clk: &Clock, 
        ctx: &mut TxContext
    ) {
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let (balance_a, balance_b) = movescription_to_lpt<T>(tick_record, movescription);
        let positions = movescription::tick_record_borrow_mut_df_internal<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        let (remain_balance_a, remain_balance_b) = if(table::contains(&positions.positions, sender)){
            let position_nft = table::borrow_mut(&mut positions.positions, sender);
            add_liquidity_with_swap(config, pool, position_nft, balance_a, balance_b, clk)
        }else{
            let position_nft = pool::open_position(
                config,
                pool,
                CETUS_MIN_TICK_U32, 
                CETUS_MAX_TICK_U32,
                ctx
            );
            let (remain_balance_a, remain_balance_b) = add_liquidity_with_swap(config, pool, &mut position_nft, balance_a, balance_b, clk);
            table::add(&mut positions.positions, sender, position_nft);
            (remain_balance_a, remain_balance_b)
        };
        if(balance::value(&remain_balance_a) > 0){
            transfer::public_transfer(coin::from_balance(remain_balance_a, ctx), tx_context::sender(ctx));
        }else{
            balance::destroy_zero(remain_balance_a);
        };
        if(balance::value(&remain_balance_b) > 0){
            transfer::public_transfer(coin::from_balance(remain_balance_b, ctx), tx_context::sender(ctx));
        }else{
            balance::destroy_zero(remain_balance_b);
        };
    }

    public entry fun remove_liquidity<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        delta_liquidity: u128, 
        clk: &Clock, 
        ctx: &mut TxContext
    ) {
        let (movescription, balance_t) = do_remove_liquidity(config, pool, tick_record, delta_liquidity, clk, ctx);
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(movescription, sender);
        if(balance::value(&balance_t)>0){
            transfer::public_transfer(coin::from_balance(balance_t, ctx), sender);
        }else{
            balance::destroy_zero(balance_t);
        };
    }

    public fun do_remove_liquidity<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2,
        delta_liquidity: u128, 
        clk: &Clock, 
        ctx: &mut TxContext
    ): (Movescription, Balance<T>) {
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let positions = movescription::tick_record_borrow_mut_df_internal<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&positions.positions, sender), ErrorNoLiquidity);
        let position_nft = table::borrow_mut(&mut positions.positions, sender);
        let (balance_a, balance_b) = pool::remove_liquidity(config, pool, position_nft, delta_liquidity, clk);
        let (movescription, remain_balance_a) = movescription::coin_to_movescription(tick_record, balance_b, option::none(), option::none(), balance_a, ctx);
        (movescription, remain_balance_a)
    }

    public entry fun remove_all_liquidity<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        clk: &Clock, 
        ctx: &mut TxContext
    ) {
        let (movescription, balance_t) = do_remove_all_liquidity(config, pool, tick_record, clk, ctx);
        transfer::public_transfer(movescription, tx_context::sender(ctx));
        let sender = tx_context::sender(ctx);
        if(balance::value(&balance_t)>0){
            transfer::public_transfer(coin::from_balance(balance_t, ctx), sender);
        }else{
            balance::destroy_zero(balance_t);
        };
    }

    public fun do_remove_all_liquidity<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        clk: &Clock, ctx: &mut TxContext
    ): (Movescription, Balance<T>) {
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let positions = movescription::tick_record_borrow_mut_df_internal<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&positions.positions, sender), ErrorNoLiquidity);
        let position_nft = table::borrow_mut(&mut positions.positions, sender);
        let liquidity = position::liquidity(position_nft);
        let (balance_a, balance_b) = pool::remove_liquidity(config, pool, position_nft, liquidity, clk);
        //it is hard to clean all the liquidity, so we do not close the position.
        //pool::close_position(config, pool, position_nft);
        let (movescription, remain_balance_a) = movescription::coin_to_movescription(tick_record, balance_b, option::none(), option::none(), balance_a, ctx);
        (movescription, remain_balance_a)
    }

    public entry fun collect_fee<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        ctx: &mut TxContext
    ) {
        let (balance_sui, balance_t) = do_collect_fee(config, pool, tick_record, ctx);
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(coin::from_balance(balance_sui,ctx), sender);
        transfer::public_transfer(coin::from_balance(balance_t, ctx), sender);
    }

    /// Collect fee with reference, reward the reference with ReferenceFeeRewardPercent of the fee
    public entry fun collect_fee_with_reference<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        reference: address, 
        ctx: &mut TxContext
    ) {
        let (balance_sui, balance_t) = do_collect_fee(config, pool, tick_record, ctx);
        
        let reward_sui_amount = balance::value(&balance_sui) * ReferenceFeeRewardPercent/100;
        let reward_t_amount = balance::value(&balance_t) * ReferenceFeeRewardPercent/100;
        let reward_sui = balance::split(&mut balance_sui, reward_sui_amount);
        let reward_t = balance::split(&mut balance_t, reward_t_amount);
        transfer::public_transfer(coin::from_balance(reward_sui, ctx), reference);
        transfer::public_transfer(coin::from_balance(reward_t, ctx), reference);
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(coin::from_balance(balance_sui,ctx), sender);
        transfer::public_transfer(coin::from_balance(balance_t, ctx), sender);
    }

    public fun do_collect_fee<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        ctx: &mut TxContext
    ): (Balance<T>, Balance<SUI>) {
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let positions = movescription::tick_record_borrow_df<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&positions.positions, sender), ErrorNoLiquidity);
        let position_nft = table::borrow(&positions.positions, sender);
        pool::collect_fee(config, pool, position_nft, true)
    }

    public entry fun buy<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        sui: Coin<SUI>, 
        clk: &Clock, 
        ctx: &mut TxContext
    ) {
        let (balance_t, balance_sui) = do_buy(config, pool, tick_record, sui, clk);
        let sender = tx_context::sender(ctx);
        if(balance::value(&balance_sui) > 0){
            transfer::public_transfer(coin::from_balance(balance_sui, ctx), sender);
        }else{
            balance::destroy_zero(balance_sui);
        };
        if(balance::value(&balance_t) > 0){
            transfer::public_transfer(coin::from_balance(balance_t, ctx), sender);
        }else{
            balance::destroy_zero(balance_t);
        };
    }

    public fun do_buy<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2, 
        sui: Coin<SUI>, 
        clk: &Clock
    ) : (Balance<T>, Balance<SUI>) {
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        swap(config, pool, balance::zero<T>(), coin::into_balance(sui), false, clk)
    }

    public entry fun deposit_reward<T: drop>(
        config: &GlobalConfig,
        vault: &mut RewarderGlobalVault,
        tick_record: &mut TickRecordV2, 
        value: u64,
        publisher: &mut Publisher,
    ) {
        do_deposit_reward<T>(config, vault, tick_record, value, publisher);
    }

    public fun do_deposit_reward<T: drop>(
        config: &GlobalConfig,
        vault: &mut RewarderGlobalVault,
        tick_record: &mut TickRecordV2, 
        value: u64,
        publisher: &mut Publisher,
    ) {
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::is_movescription_publisher(publisher), ErrorInvalidCap);

        let balance_bm = movescription::borrow_mut_incentive<T>(tick_record);
        let balance_take = if (value != 0) {
            balance::split<T>(balance_bm, value)
        } else {
            balance::withdraw_all<T>(balance_bm)
        };
        rewarder::deposit_reward<T>(config, vault, balance_take);
    }

    public entry fun collect_reward<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2,
        vault: &mut RewarderGlobalVault,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let reward_balance = do_collect_reward(config, pool, tick_record, vault, clock, ctx);
        transfer::public_transfer(coin::from_balance(reward_balance, ctx), tx_context::sender(ctx));
    }

    public fun do_collect_reward<T: drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        tick_record: &mut TickRecordV2,
        vault: &mut RewarderGlobalVault,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Balance<T> {
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let positions = movescription::tick_record_borrow_mut_df_internal<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&positions.positions, sender), ErrorNoLiquidity);
        let position_nft = table::borrow_mut(&mut positions.positions, sender); 
        pool::collect_reward<T, SUI, T>(
            config,
            pool,
            position_nft,
            vault,
            true,
            clock
        )
    }

    fun add_liquidity_with_swap<T:drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        position_nft: &mut Position, 
        balance_a: Balance<T>, 
        balance_b: Balance<SUI>, 
        clk: &Clock
    ): (Balance<T>, Balance<SUI>) {
        if(balance::value(&balance_a) == 0 || balance::value(&balance_b) == 0){
            let a2b = balance::value(&balance_a) != 0; 
            let (swap_balance_a, swap_balance_b) = swap(config, pool, balance_a, balance_b, a2b, clk);
            let (remain_balance_a, remain_balance_b, _) = add_liquidity_internal(config, pool, position_nft, swap_balance_a, swap_balance_b, clk);
            (remain_balance_a, remain_balance_b)
        }else{
            let (remain_balance_a, remain_balance_b, is_fixed_a) = add_liquidity_internal(config, pool, position_nft, balance_a, balance_b, clk);
            if(balance::value(&remain_balance_a) > 0 || balance::value(&remain_balance_b) > 0){
                let (swap_balance_a, swap_balance_b) = swap(config, pool, remain_balance_a, remain_balance_b, !is_fixed_a, clk);
                let (remain_balance_a, remain_balance_b, _) = add_liquidity_internal(config, pool, position_nft, swap_balance_a, swap_balance_b, clk);
                (remain_balance_a, remain_balance_b)
            }else{
                (remain_balance_a, remain_balance_b)
            }
        }
    }

    fun add_liquidity_internal<T:drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<T,SUI>, 
        position_nft: &mut Position, 
        balance_a: Balance<T>, 
        balance_b: Balance<SUI>, 
        clk: &Clock
    ): (Balance<T>, Balance<SUI>, bool) {
        let amount_a = balance::value(&balance_a);
        let amount_b = balance::value(&balance_b);
        let current_tick_index = pool::current_tick_index(pool);
        let current_sqrt_price = pool::current_sqrt_price(pool);
        let (lower, upper) = position::tick_range(position_nft);
        let (delta_liquidity,_, _, is_fixed_a) = get_liquidity_by_amount(lower, upper, current_tick_index, current_sqrt_price, amount_a, amount_b); 
        let receipt = pool::add_liquidity(config, pool, position_nft, delta_liquidity, clk);
        let (receipt_amount_a, receipt_amount_b) = pool::add_liquidity_pay_amount(&receipt);
        let new_balance_a = balance::split(&mut balance_a, receipt_amount_a);
        let new_balance_b = balance::split(&mut balance_b, receipt_amount_b);
        pool::repay_add_liquidity(config, pool, new_balance_a, new_balance_b, receipt);
        (balance_a, balance_b, is_fixed_a)
    }

    fun get_liquidity_by_amount(
        lower_index: I32,
        upper_index: I32,
        current_tick_index: I32,
        current_sqrt_price: u128,
        amount_a: u64,
        amount_b: u64,
    ): (u128, u64, u64, bool) {
        let (liqudity, l_amount_a, l_amount_b) = clmm_math::get_liquidity_by_amount(lower_index, upper_index, current_tick_index, current_sqrt_price, amount_b, false);
        if(l_amount_a <= amount_a && l_amount_b <= amount_b){
            (liqudity, l_amount_a, l_amount_b, false)
        }else{
            let (liqudity, l_amount_a, l_amount_b) = clmm_math::get_liquidity_by_amount(lower_index, upper_index, current_tick_index, current_sqrt_price, amount_a, true);
            assert!(l_amount_a <= amount_a && l_amount_b <= amount_b, ErrorInvalidState);
            (liqudity, l_amount_a, l_amount_b, true)
        }
    }

    fun swap<CoinTypeA, CoinTypeB>(
        config: &GlobalConfig, 
        pool: &mut Pool<CoinTypeA, CoinTypeB>, 
        balance_a: Balance<CoinTypeA>, 
        balance_b: Balance<CoinTypeB>,
        a2b: bool, 
        clk: &Clock
    ): (Balance<CoinTypeA>, Balance<CoinTypeB>) {
        let amount_a = balance::value(&balance_a);
        let amount_b = balance::value(&balance_b);

        let amount = if (a2b) amount_a/2 else amount_b/2;
        let sqrt_price_limit = get_default_sqrt_price_limit(a2b);
        let (receive_a, receive_b, flash_receipt) = pool::flash_swap<CoinTypeA, CoinTypeB>(
            config,
            pool,
            a2b,
            true,
            amount,
            sqrt_price_limit,
            clk
        );
        let (in_amount, _out_amount) = (
            pool::swap_pay_amount(&flash_receipt),
            if (a2b) balance::value(&receive_b) else balance::value(&receive_a)
        );

        // pay for flash swap
        let (pay_coin_a, pay_coin_b) = if (a2b) {
            (balance::split(&mut balance_a, in_amount), balance::zero<CoinTypeB>())
        } else {
            (balance::zero<CoinTypeA>(), balance::split(&mut balance_b, in_amount))
        };

        pool::repay_flash_swap<CoinTypeA, CoinTypeB>(
            config,
            pool,
            pay_coin_a,
            pay_coin_b,
            flash_receipt
        );

        balance::join(&mut balance_a, receive_a);
        balance::join(&mut balance_b, receive_b);
        (balance_a, balance_b)
    }

    fun get_default_sqrt_price_limit(a2b: bool): u128{
        if(a2b){
            tick_math::min_sqrt_price()
        }else{
            tick_math::max_sqrt_price()
        }
    }

    fun movescription_to_lpt<T: drop>(
        tick_record: &mut TickRecordV2, 
        movescription: Movescription
    ): (Balance<T>, Balance<SUI>) {
        let (balance_sui, locked, metadata, balance_t) = movescription::movescription_to_coin<T>(tick_record, movescription);
        //Currently, we do not support Movescription has LockedMovescription and Metadata.
        assert!(option::is_none(&locked), ErrorNotSupported);
        assert!(option::is_none(&metadata), ErrorNotSupported);
        option::destroy_none(locked);
        option::destroy_none(metadata);
        (balance_t, balance_sui)
    }

    const POW_2_64: u128 = 18_446_744_073_709_551_616;
    const POW_10_18: u128 = 1_000_000_000_000_000_000;
    const POW_10_9: u128 = 1_000_000_000;
    ///https://github.com/CetusProtocol/cetus-clmm-sui-sdk/blob/a28b7220b7ef4fd3ec361abfddd0aaf9413946d8/src/math/tick.ts#L164
    fun price_to_sqrt_price_x64(
        amount_a: u64, 
        amount_b: u64, 
        decimals_a: u8, 
        decimals_b: u8
    ): u128 {
        let a = (amount_a as u128);
        let b = (amount_b as u128);
        let decimal_diff = (math::diff((decimals_a as u64), (decimals_b as u64)) as u8);
        let sqrt_price = math::sqrt_u128(b * (math::pow(10, (decimal_diff as u8)) as u128) * POW_10_18/ a)*POW_2_64/POW_10_9;
        sqrt_price
    }

    #[test_only]
    fun check_postion_tick_range(lower: u32, upper: u32, tick_spacing: u32){
        let lower_i32 = i32::from_u32(lower);
        let upper_i32 = i32::from_u32(upper);
        assert!(i32::lt(lower_i32, upper_i32), 1);
        assert!(i32::gte(lower_i32, tick_math::min_tick()), 2);
        assert!(i32::lte(upper_i32, tick_math::max_tick()), 3);
        assert!(i32::mod(lower_i32, i32::from(tick_spacing)) == i32::zero(), 4);
        assert!(i32::mod(upper_i32, i32::from(tick_spacing)) == i32::zero(), 5);
    }

    #[test]
    fun test_check_postion_tick_range(){
        let min_tick = tick_math::min_tick();
        // i32::mod min_tick is a negative number, so we use sub function not add.
        let suitable_min_tick = i32::sub(min_tick,i32::mod(min_tick, i32::from(CETUS_TICK_SPACING)));
        let max_tick = tick_math::max_tick();
        let suitable_max_tick = i32::sub(max_tick,i32::mod(max_tick, i32::from(CETUS_TICK_SPACING)));
        let suitable_min_tick_u32 = i32::as_u32(suitable_min_tick);
        let suitable_max_tick_u32 = i32::as_u32(suitable_max_tick);
        std::debug::print(&suitable_min_tick_u32);
        std::debug::print(&suitable_max_tick_u32);
        check_postion_tick_range(suitable_min_tick_u32, suitable_max_tick_u32, CETUS_TICK_SPACING);
    }

    #[test]
    fun test_price_to_sqrt_price_x64(){
        let amount_a = 500_000000000;
        let amount_b = 100_000000000;
        let decimals_a:u8 = 9;
        let decimals_b:u8 = 9;
        let sqrt_price = price_to_sqrt_price_x64(amount_a, amount_b, decimals_a, decimals_b);
        std::debug::print(&sqrt_price);
        //js result:
        // console.log(TickMath.priceToSqrtPriceX64(
        // d(100_000000000.00000000/500_000000000.0000000000),
        // 9,
        // 9
        // ).toString());
        //8249634742471189717
        assert!(sqrt_price == 8249634733248593564, 1);
        let tick_at_sqrt_price = tick_math::get_tick_at_sqrt_price(sqrt_price);
        std::debug::print(&tick_at_sqrt_price);
    }

    #[test]
    fun test_price_to_sqrt_price_x64_float(){
        let amount_a = 50_000000000;
        let amount_b = 100_000000000;
        let decimals_a:u8 = 9;
        let decimals_b:u8 = 9;
        let sqrt_price = price_to_sqrt_price_x64(amount_a, amount_b, decimals_a, decimals_b);
        std::debug::print(&sqrt_price);
        //js result:
        // console.log(TickMath.priceToSqrtPriceX64(
        //     d(100_000000000.00000000/50_000000000.0000000000),
        //     9,
        //     9
        //     ).toString());
        //26087635650665564424
        assert!(sqrt_price == 26087635643783175544, 1);
        let tick_at_sqrt_price = tick_math::get_tick_at_sqrt_price(sqrt_price);
        std::debug::print(&tick_at_sqrt_price);
    }

    #[test]
    fun test_real_case(){
        //MOVE
        let amount_a = 462962_000000000;
        //SUI
        let amount_b = 200000000;
        let decimals_a:u8 = 9;
        let decimals_b:u8 = 9;
        let sqrt_price = price_to_sqrt_price_x64(amount_a, amount_b, decimals_a, decimals_b);
        std::debug::print(&sqrt_price);
        let tick_at_sqrt_price = tick_math::get_tick_at_sqrt_price(sqrt_price);
        std::debug::print(&tick_at_sqrt_price);
        let (liqudity, a_result, b_result, is_fixed_a) = get_liquidity_by_amount(i32::from_u32(CETUS_MIN_TICK_U32), i32::from_u32(CETUS_MAX_TICK_U32), tick_at_sqrt_price, sqrt_price, amount_a, amount_b);
        std::debug::print(&liqudity);
        std::debug::print(&a_result);
        std::debug::print(&b_result);
        std::debug::print(&is_fixed_a);
    }

    #[test]
    fun test_real_case2(){
        //MOVE
        let amount_a = 462962_000000000;
        //SUI
        let amount_b = 200000000;
        let sqrt_price:u128 = 12124436137094855;
        let tick_index = i32::from_u32(4294820740);
        let (liqudity, a_result, b_result, _is_fixed_a) = get_liquidity_by_amount(i32::from_u32(CETUS_MIN_TICK_U32), i32::from_u32(CETUS_MAX_TICK_U32), tick_index, sqrt_price, amount_a, amount_b);
        std::debug::print(&liqudity);
        std::debug::print(&a_result);
        std::debug::print(&b_result);
    }

    #[test]
    fun min_max_tick(){
        let min = tick_math::min_tick();
        std::debug::print(&min);
        let max = tick_math::max_tick();
        std::debug::print(&max);
    }
}