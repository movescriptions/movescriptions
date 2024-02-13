module smartinscription::movescription_to_amm{
    use std::option;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::Clock;
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::coin;
    use sui::table::{Self, Table};
    use sui::transfer;
    use cetus_clmm::factory::{Self, Pools};
    use cetus_clmm::pool::{Self, Pool};
    use cetus_clmm::position::{Self, Position};
    use cetus_clmm::config::{GlobalConfig};
    use cetus_clmm::tick_math;
    use cetus_clmm::clmm_math;
    use smartinscription::movescription::{Self, Movescription, MCoin, TickRecordV2};

    const CETUS_TICK_SPACING: u32 = 200;

    const ErrorTreasuryNotInited: u64 = 1;
    const ErrorCoinTypeMissMatch: u64 = 2;
    const ErrorNotSupported: u64 = 3;
    const ErrorPoolNotInited: u64 = 4;
    const ErrorPoolAlreadyInited: u64 = 5;
    const ErrorNoLiquidity: u64 = 6;
    const ErrorInvalidInitLiquidity: u64 = 7;
    const ErrorInvalidState: u64 = 8;

    struct Positions has store{
        positions: Table<address, Position>,
    }

    /// Initialize a pool with liquidity
    public entry fun init_pool<T: drop>(pools: &mut Pools, config: &GlobalConfig, tick_record: &mut TickRecordV2, movescription: Movescription, clk: &Clock, ctx: &mut TxContext){
        assert!(movescription::is_treasury_inited(tick_record), ErrorTreasuryNotInited);
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(!movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolAlreadyInited);

        let (balance_a, balance_b) = movescription_to_lpt<T>(tick_record, movescription);
        let amount_a = balance::value(&balance_a);
        let amount_b = balance::value(&balance_b);
        assert!(amount_a > 0, ErrorInvalidInitLiquidity);
        assert!(amount_b > 0, ErrorInvalidInitLiquidity);
        let initialize_price = (amount_a as u128) / (amount_b as u128);

        let (position, coin_a, coin_b) = factory::create_pool_with_liquidity<MCoin<T>,SUI>(
            pools, config, CETUS_TICK_SPACING, initialize_price, std::string::utf8(b""), 
            tick_math::tick_bound(),
            tick_math::tick_bound(),
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

    public entry fun add_liquidity<T: drop>(config: &GlobalConfig, pool: &mut Pool<MCoin<T>,SUI>, tick_record: &mut TickRecordV2, movescription: Movescription, clk: &Clock, ctx: &mut TxContext){
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let (balance_a, balance_b) = movescription_to_lpt<T>(tick_record, movescription);
        //TODO auto swap between SUI and MCoin<T>
        let positions = movescription::tick_record_borrow_mut_df_internal<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        let (remain_balance_a, remain_balance_b) = if(table::contains(&positions.positions, sender)){
            let position_nft = table::borrow_mut(&mut positions.positions, sender);
            add_liquidity_with_swap(config, pool, position_nft, balance_a, balance_b, clk)
        }else{
            let position_nft = pool::open_position(
                config,
                pool,
                tick_math::tick_bound(),
                tick_math::tick_bound(),
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

    public entry fun remove_liquidity<T: drop>(config: &GlobalConfig, pool: &mut Pool<MCoin<T>,SUI>, tick_record: &mut TickRecordV2, delta_liquidity: u128, clk: &Clock, ctx: &mut TxContext){
        let movescription = do_remove_liquidity(config, pool, tick_record, delta_liquidity, clk, ctx);
        transfer::public_transfer(movescription, tx_context::sender(ctx));
    }

    public fun do_remove_liquidity<T: drop>(config: &GlobalConfig, pool: &mut Pool<MCoin<T>,SUI>, tick_record: &mut TickRecordV2, delta_liquidity: u128, clk: &Clock, ctx: &mut TxContext) : Movescription{
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let positions = movescription::tick_record_borrow_mut_df_internal<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&positions.positions, sender), ErrorNoLiquidity);
        let position_nft = table::borrow_mut(&mut positions.positions, sender);
        let (balance_a, balance_b) = pool::remove_liquidity(config, pool, position_nft, delta_liquidity, clk);
        let movescription = movescription::coin_to_movescription(tick_record, balance_b, option::none(), option::none(), balance_a, ctx);
        movescription
    }

    public entry fun remove_all_liquidity<T: drop>(config: &GlobalConfig, pool: &mut Pool<MCoin<T>,SUI>, tick_record: &mut TickRecordV2, clk: &Clock, ctx: &mut TxContext){
        let movescription = do_remove_all_liquidity(config, pool, tick_record, clk, ctx);
        transfer::public_transfer(movescription, tx_context::sender(ctx));
    }

    public fun do_remove_all_liquidity<T: drop>(config: &GlobalConfig, pool: &mut Pool<MCoin<T>,SUI>, tick_record: &mut TickRecordV2, clk: &Clock, ctx: &mut TxContext) : Movescription{
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let positions = movescription::tick_record_borrow_mut_df_internal<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&positions.positions, sender), ErrorNoLiquidity);
        let position_nft = table::remove(&mut positions.positions, sender);
        let liquidity = position::liquidity(&position_nft);
        let (balance_a, balance_b) = pool::remove_liquidity(config, pool, &mut position_nft, liquidity, clk);
        pool::close_position(config, pool, position_nft);
        let movescription = movescription::coin_to_movescription(tick_record, balance_b, option::none(), option::none(), balance_a, ctx);
        movescription
    }

    public entry fun collect_fee<T: drop>(config: &GlobalConfig, pool: &mut Pool<MCoin<T>,SUI>, tick_record: &mut TickRecordV2, ctx: &mut TxContext){
        let (balance_sui, balance_t) = do_collect_fee(config, pool, tick_record, ctx);
        transfer::public_transfer(coin::from_balance(balance_sui,ctx), tx_context::sender(ctx));
        transfer::public_transfer(coin::from_balance(balance_t, ctx), tx_context::sender(ctx));
    }

    public fun do_collect_fee<T: drop>(config: &GlobalConfig, pool: &mut Pool<MCoin<T>,SUI>, tick_record: &mut TickRecordV2, ctx: &mut TxContext) :(Balance<MCoin<T>>, Balance<SUI>){
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        assert!(movescription::tick_record_exists_df<Positions>(tick_record), ErrorPoolNotInited);
        let positions = movescription::tick_record_borrow_df<Positions>(tick_record);
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&positions.positions, sender), ErrorNoLiquidity);
        let position_nft = table::borrow(&positions.positions, sender);
        pool::collect_fee(config, pool, position_nft, true)
    }

    fun add_liquidity_with_swap<T:drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<MCoin<T>,SUI>, 
        position_nft: &mut Position, 
        balance_a: Balance<MCoin<T>>, 
        balance_b: Balance<SUI>, 
        clk: &Clock):(Balance<MCoin<T>>, Balance<SUI>){
        let (remain_balance_a, remain_balance_b) = add_liquidity_internal(config, pool, position_nft, balance_a, balance_b, clk);
        if(balance::value(&remain_balance_a) > 0 || balance::value(&remain_balance_b) > 0){
            let (swap_balance_a, swap_balance_b) = swap(config, pool, remain_balance_a, remain_balance_b, clk);
            add_liquidity_internal(config, pool, position_nft, swap_balance_a, swap_balance_b, clk)
        }else{
            (remain_balance_a, remain_balance_b)
        }
    }

    fun add_liquidity_internal<T:drop>(
        config: &GlobalConfig, 
        pool: &mut Pool<MCoin<T>,SUI>, 
        position_nft: &mut Position, 
        balance_a: Balance<MCoin<T>>, 
        balance_b: Balance<SUI>, 
        clk: &Clock):(Balance<MCoin<T>>, Balance<SUI>){
        let amount_a = balance::value(&balance_a);
        let amount_b = balance::value(&balance_b);
        let current_tick_index = pool::current_tick_index(pool);
        let current_sqrt_price = pool::current_sqrt_price(pool);
        let delta_liquidity = {
            let (liqudity, l_amount_a, l_amount_b) = clmm_math::get_liquidity_by_amount(tick_math::min_tick(), tick_math::max_tick(), current_tick_index, current_sqrt_price, amount_b, false);
            if(l_amount_a >= amount_a && l_amount_b >= amount_b){
                liqudity
            }else{
                let (liqudity, l_amount_a, l_amount_b) = clmm_math::get_liquidity_by_amount(tick_math::min_tick(), tick_math::max_tick(), current_tick_index, current_sqrt_price, amount_a, true);
                assert!(l_amount_a >= amount_a && l_amount_b >= amount_b, ErrorInvalidState);
                liqudity
            }
        };
        let receipt = pool::add_liquidity(config, pool, position_nft, delta_liquidity, clk);
        let (receipt_amount_a, receipt_amount_b) = pool::add_liquidity_pay_amount(&receipt);
        if(amount_a == receipt_amount_a && amount_b == receipt_amount_b){
            pool::repay_add_liquidity(config, pool, balance_a, balance_b, receipt);
            (balance::zero<MCoin<T>>(), balance::zero<SUI>())
        }else if(amount_b == receipt_amount_b){
            let new_balance_a = balance::split(&mut balance_a, receipt_amount_a);
            pool::repay_add_liquidity(config, pool, new_balance_a, balance_b, receipt);
            (balance_a, balance::zero<SUI>())
        }else if(amount_a == receipt_amount_a){
            let new_balance_b = balance::split(&mut balance_b, receipt_amount_b);
            pool::repay_add_liquidity(config, pool, balance_a, new_balance_b, receipt);
            (balance::zero<MCoin<T>>(), balance_b)
        }else{
            abort ErrorInvalidState
        }
    }

    fun swap<CoinTypeA, CoinTypeB>(
        config: &GlobalConfig, 
        pool: &mut Pool<CoinTypeA, CoinTypeB>, 
        balance_a: Balance<CoinTypeA>, 
        balance_b: Balance<CoinTypeB>, 
        clk: &Clock) : (Balance<CoinTypeA>, Balance<CoinTypeB>){
        let amount_a = balance::value(&balance_a);
        let amount_b = balance::value(&balance_b);
        let a2b = amount_a >0;

        let amount = if (a2b) amount_a/2 else amount_b/2;
        let current_sqrt_price = pool::current_sqrt_price(pool);
        let (receive_a, receive_b, flash_receipt) = pool::flash_swap<CoinTypeA, CoinTypeB>(
            config,
            pool,
            a2b,
            true,
            amount,
            current_sqrt_price,
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

    fun movescription_to_lpt<T: drop>(tick_record: &mut TickRecordV2, movescription: Movescription): (Balance<MCoin<T>>, Balance<SUI>){
        let (balance_sui, locked, metadata, balance_t) = movescription::movescription_to_coin<T>(tick_record, movescription);
        //Currently, we do not support Movescription has LockedMovescription and Metadata.
        assert!(option::is_none(&locked), ErrorNotSupported);
        assert!(option::is_none(&metadata), ErrorNotSupported);
        option::destroy_none(locked);
        option::destroy_none(metadata);
        (balance_t, balance_sui)
    }
}