module smartinscription::movecoin{
    use std::option;
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use smartinscription::movescription::{Self, TickRecordV2, InitTreasuryArgs};
    use smartinscription::assert_util;
    use smartinscription::tick_name;

    friend smartinscription::init;

    struct MOVECOIN has drop {}

    #[lint_allow(share_owned)]
    fun init(witness: MOVECOIN, ctx: &mut TxContext) {
        let decimals = movescription::mcoin_decimals();
        let (treasury, metadata) = coin::create_currency(witness, decimals, tick_name::move_tick(), tick_name::move_tick(), b"MOVE coin of Movescription", option::none(), ctx);
        let args = movescription::new_init_treasury_args(std::ascii::string(tick_name::move_tick()), treasury, metadata, ctx);
        transfer::public_share_object(args);
    }

    public(friend) fun init_movecoin<T: drop>(tick_record: &mut TickRecordV2, init_args: &mut InitTreasuryArgs<T>) {
        assert_util::assert_tick_record(tick_record, tick_name::move_tick());
        movescription::init_treasury(tick_record, init_args);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(MOVECOIN{}, ctx);
    }
}