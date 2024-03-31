module smartinscription::mint_ratio_50_factory {
    use std::option;
    use sui::tx_context::{Self,TxContext};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::coin::{Self,Coin};
    use sui::clock::{Self, Clock};
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2, Movescription};
    use smartinscription::assert_util;
    use smartinscription::tick_factory;

    friend smartinscription::init;

    const SUI_BASE: u128 = 1_000_000_000;

    const EDeprecatedFunction: u64 = 0;
    const ENotEnoughSui: u64 = 1;
    const EAlreadyMax: u64 = 2;
    const EUnFinished: u64 = 3;
    const ENotStart: u64 = 4;

    struct WITNESS has drop {}

    struct MintRatioFactory has store {
        amount_per_sui: u128, 
        start_time_ms: u64,
        min_value_sui: u64, 
        max_value_sui: u64,
        participants: TableVec<address>, 
        minted_per_user: Table<address, u64>,
    }

    public entry fun deploy(
        deploy_record: &mut DeployRecord,
        tick_tick_record: &mut TickRecordV2, 
        tick_name: Movescription,
        total_supply: u64,
        amount_per_sui: u128, 
        start_time_ms: u64,
        min_value_sui: u64, 
        max_value_sui: u64,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        do_deploy(deploy_record, tick_tick_record, tick_name, total_supply, amount_per_sui, start_time_ms, min_value_sui, max_value_sui, clk, ctx);
    }

    public fun do_deploy(
        deploy_record: &mut DeployRecord,
        tick_tick_record: &mut TickRecordV2, 
        tick_name: Movescription,
        total_supply: u64,
        amount_per_sui: u128, 
        start_time_ms: u64,
        min_value_sui: u64, 
        max_value_sui: u64,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        assert_util::assert_tick_tick(&tick_name);
        let now = clock::timestamp_ms(clk);
        if (start_time_ms < now) {
            start_time_ms = now;
        };

        let tick_record = tick_factory::do_deploy(deploy_record, tick_tick_record, tick_name, total_supply, true, WITNESS{}, clk, ctx);
        after_deploy(tick_record, amount_per_sui, start_time_ms, min_value_sui, max_value_sui, ctx);
    }

    #[lint_allow(share_owned)]
    fun after_deploy(
        tick_record: TickRecordV2,
        amount_per_sui: u128, 
        start_time_ms: u64,
        min_value_sui: u64, 
        max_value_sui: u64,
        ctx: &mut TxContext,
    ) {
        let factory = MintRatioFactory {
            amount_per_sui,
            start_time_ms, 
            min_value_sui,
            max_value_sui,
            participants: table_vec::empty<address>(ctx),
            minted_per_user: table::new<address, u64>(ctx),
        };
        movescription::tick_record_add_df(&mut tick_record, factory, WITNESS{});
        transfer::public_share_object(tick_record);
    }

    public entry fun mint_v2(
        tick_record: &mut TickRecordV2,
        fee_sui: &mut Coin<SUI>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        let ms = do_mint_v2(tick_record, fee_sui, clk, ctx);
        transfer::public_transfer(ms, tx_context::sender(ctx));
    }

    public fun do_mint_v2(
        tick_record: &mut TickRecordV2,
        fee_sui: &mut Coin<SUI>,
        clk: &Clock,
        ctx: &mut TxContext
    ): Movescription {
        let remain = movescription::tick_record_v2_remain(tick_record);
        let mint_ratio_factory = movescription::tick_record_borrow_mut_df<MintRatioFactory, WITNESS>(tick_record, WITNESS{});
        assert!(clock::timestamp_ms(clk) > mint_ratio_factory.start_time_ms, ENotStart);
        let sui_value = coin::value(fee_sui);
        assert!(sui_value >= mint_ratio_factory.min_value_sui, ENotEnoughSui);

        let sender = tx_context::sender(ctx);
        if (table::contains<address, u64>(&mint_ratio_factory.minted_per_user, sender)) {
            let minted_value = table::borrow_mut<address, u64>(&mut mint_ratio_factory.minted_per_user, sender);
            if (sui_value + *minted_value > mint_ratio_factory.max_value_sui) {
                sui_value = mint_ratio_factory.max_value_sui - *minted_value;
            };
            assert!(sui_value > 0, EAlreadyMax);
            *minted_value = *minted_value + sui_value;
        } else {
            if (sui_value > mint_ratio_factory.max_value_sui) {
                sui_value = mint_ratio_factory.max_value_sui;
            };
            table::add<address, u64>(&mut mint_ratio_factory.minted_per_user, sender, sui_value);
            table_vec::push_back<address>(&mut mint_ratio_factory.participants, sender);
        };

        let amount = ((((sui_value as u128) * (mint_ratio_factory.amount_per_sui)) / SUI_BASE) as u64);

        if (amount > remain) {
            amount = remain;
            sui_value = ((((amount as u128) * SUI_BASE) / (mint_ratio_factory.amount_per_sui)) as u64);
        };
        let locked_sui = coin::into_balance<SUI>(coin::split<SUI>(fee_sui, sui_value, ctx));
        let minted_movescription = movescription::do_mint_with_witness(tick_record, locked_sui, amount, option::none(), WITNESS{}, ctx);
        minted_movescription
    }

    public entry fun mint(
        _tick_record: &mut TickRecordV2,
        _fee_sui: &mut Coin<SUI>,
        _ctx: &mut TxContext
    ) {
        abort EDeprecatedFunction
    }

    public fun do_mint(
        _tick_record: &mut TickRecordV2,
        _fee_sui: &mut Coin<SUI>,
        _ctx: &mut TxContext
    ): Movescription {
        abort EDeprecatedFunction
    }

    public entry fun clean(tick_record: &mut TickRecordV2, times: u64) {
        do_clean(tick_record, times);
    }

    public fun do_clean(tick_record: &mut TickRecordV2, times: u64) {
        assert!(movescription::tick_record_v2_remain(tick_record) == 0, EUnFinished);
        let mint_ratio_factory = movescription::tick_record_borrow_mut_df<MintRatioFactory, WITNESS>(tick_record, WITNESS{});
        let participants_num = table_vec::length(&mint_ratio_factory.participants);
        while (participants_num > 0 && times > 0) {
            let participant = table_vec::pop_back<address>(&mut mint_ratio_factory.participants);
            let _ = table::remove<address, u64>(&mut mint_ratio_factory.minted_per_user, participant);
            participants_num = participants_num - 1;
            times = times - 1;
        };
    }
}
