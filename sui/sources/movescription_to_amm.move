module smartinscription::movescription_to_amm{
    use std::option;
    use sui::tx_context::TxContext;
    use sui::clock::Clock;
    use sui::sui::SUI;
    use sui::balance;
    use cetus_clmm::factory::{Self, Pools};
    use cetus_clmm::pool::{Self, Pool};
    use cetus_clmm::position::{Position};
    use cetus_clmm::config::{GlobalConfig};
    use cetus_clmm::tick_math;
    use smartinscription::movescription::{Self, Movescription, MCoin, TickRecordV2};

    const CETUS_TICK_SPACING: u32 = 200;

    const ErrorTreasuryNotInited: u64 = 1;
    const ErrorCoinTypeMissMatch: u64 = 2;
    const ErrorNotSupported: u64 = 3;

    public fun init_pool_with_sui<T: drop>(pools: &mut Pools, config: &GlobalConfig, tick_record: &mut TickRecordV2, initialize_price: u128, clk: &Clock, ctx: &mut TxContext){
        assert!(movescription::is_treasury_inited(tick_record), ErrorTreasuryNotInited);
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        factory::create_pool<MCoin<T>, SUI>(pools, config, CETUS_TICK_SPACING, initialize_price, std::string::utf8(b""), clk, ctx);
    }

    public fun open_position<T: drop>(pool: &mut Pool<MCoin<T>, SUI>, tick_record: &mut TickRecordV2, config: &GlobalConfig, ctx: &mut TxContext){
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        let position_nft = pool::open_position(
            config,
            pool,
            tick_math::tick_bound(),
            tick_math::tick_bound(),
            ctx
        );
        movescription::tick_record_add_df_internal(tick_record, position_nft);
    }

    public fun add_liquidity<T: drop>(config: &GlobalConfig, pool: &mut Pool<MCoin<T>, SUI>, tick_record: &mut TickRecordV2, movescription: Movescription, clk: &Clock){
        assert!(movescription::check_coin_type<T>(tick_record), ErrorCoinTypeMissMatch);
        let (balance_sui, locked, metadata, balance_t) = movescription::movescription_to_coin<T>(tick_record, movescription);
        //Currently, we do not support Movescription has LockedMovescription and Metadata.
        assert!(option::is_none(&locked), ErrorNotSupported);
        assert!(option::is_none(&metadata), ErrorNotSupported);
        option::destroy_none(locked);
        option::destroy_none(metadata);
        //TODO auto swap between SUI and MCoin<T>
        let position_nft = movescription::tick_record_borrow_mut_df_internal<Position>(tick_record);
        let amount_a = balance::value(&balance_t);
        let receipt = pool::add_liquidity_fix_coin(config, pool, position_nft, amount_a, true, clk);
        pool::repay_add_liquidity(config, pool, balance_t, balance_sui, receipt);
    }
}