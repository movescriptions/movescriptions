module smartinscription::mint_get_factory {
    use std::option::{Self, Option};
    use sui::tx_context::{Self,TxContext};
    use sui::transfer;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self,Coin};
    use sui::clock::Clock;
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2, Movescription};
    use smartinscription::tick_name;
    use smartinscription::assert_util;
    use smartinscription::util;
    use smartinscription::tick_factory;

    friend smartinscription::init;

    const TEST_TOTAL_SUPPLY: u64 = 0xFFFFFFFFFFFFFFFF; // 18446744073709551615
    
    const ErrorInvalidInitLockedArgs: u64 = 1;
    const ErrorInvalidMintFunction: u64 = 2;
    
    struct WITNESS has drop {}

    struct MintGetFactory has store {
        amount_per_mint: u64, 
        init_locked_sui: u64, 
        init_locked_move: u64,
    }

    #[lint_allow(share_owned)]
    /// Deploy the `TEST` tick
    public fun deploy_test_tick(deploy_record: &mut DeployRecord, ctx: &mut TxContext) {
        if(movescription::is_deployed(deploy_record, tick_name::test_tick())){
            return
        };
        let tick_record = movescription::internal_deploy_with_witness(deploy_record, std::ascii::string(tick_name::test_tick()), TEST_TOTAL_SUPPLY, true, WITNESS{}, ctx);
        after_deploy(tick_record, 10000, 0, 0);
    }

    public entry fun deploy(
        deploy_record: &mut DeployRecord,
        tick_tick_record: &mut TickRecordV2, 
        tick_name: Movescription,
        total_supply: u64,
        amount_per_mint: u64, 
        init_locked_sui: u64, 
        init_locked_move: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        do_deploy(deploy_record, tick_tick_record, tick_name, total_supply, amount_per_mint, init_locked_sui, init_locked_move, clock, ctx);
    }

    /// Deploy the `tick_name` movescription by mint_get_factory
    public fun do_deploy(
        deploy_record: &mut DeployRecord,
        tick_tick_record: &mut TickRecordV2, 
        tick_name: Movescription,
        total_supply: u64,
        amount_per_mint: u64, 
        init_locked_sui: u64, 
        init_locked_move: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert_util::assert_tick_tick(&tick_name);
        //Only support locked sui or locked move
        assert!((init_locked_move==0&&init_locked_sui==0) || (init_locked_move>0&&init_locked_sui==0) || (init_locked_sui>0&&init_locked_move==0), ErrorInvalidInitLockedArgs);
        let tick_record = tick_factory::do_deploy(deploy_record, tick_tick_record, tick_name, total_supply, true, WITNESS{}, clock, ctx);
        after_deploy(tick_record, amount_per_mint, init_locked_sui, init_locked_move);
    }

    #[lint_allow(share_owned)]
    fun after_deploy(
        tick_record: TickRecordV2,
        amount_per_mint: u64, 
        init_locked_sui: u64,
        init_locked_move: u64
    ) {
        let factory = MintGetFactory{
            amount_per_mint: amount_per_mint,
            init_locked_sui: init_locked_sui, 
            init_locked_move: init_locked_move,
        };
        movescription::tick_record_add_df(&mut tick_record, factory, WITNESS{});
        transfer::public_share_object(tick_record);
    }
    

    #[lint_allow(self_transfer)]
    public entry fun mint_with_move(
        tick_record: &mut TickRecordV2,
        locked_move: Movescription,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let ms = do_mint_with_move(tick_record, locked_move,ctx);
        transfer::public_transfer(ms, sender);
    }

    public fun do_mint_with_move(
        tick_record: &mut TickRecordV2,
        locked_move: Movescription,
        ctx: &mut TxContext
    ): Movescription {
        assert_util::assert_move_tick(&locked_move);

        let mint_get_factory = movescription::tick_record_borrow_mut_df<MintGetFactory, WITNESS>(tick_record, WITNESS{});
        assert!(mint_get_factory.init_locked_move > 0, ErrorInvalidMintFunction);
        let init_locked_move = util::split_and_give_back(locked_move, mint_get_factory.init_locked_move, ctx);
        internal_mint(tick_record, mint_get_factory.amount_per_mint, balance::zero<SUI>(), option::some(init_locked_move), ctx)
    }

    #[lint_allow(self_transfer)]
    public entry fun mint_with_sui(
        tick_record: &mut TickRecordV2,
        locked_sui: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let ms = do_mint_with_sui(tick_record, locked_sui, ctx);
        transfer::public_transfer(ms, sender);
    }

    public fun do_mint_with_sui(
        tick_record: &mut TickRecordV2,
        locked_sui: Coin<SUI>,
        ctx: &mut TxContext
    ): Movescription {
        let mint_get_factory = movescription::tick_record_borrow_mut_df<MintGetFactory, WITNESS>(tick_record, WITNESS{});
        assert!(mint_get_factory.init_locked_sui > 0, ErrorInvalidMintFunction);

        let init_locked_sui = util::split_coin_and_give_back(locked_sui, mint_get_factory.init_locked_sui, ctx);
        internal_mint(tick_record, mint_get_factory.amount_per_mint, coin::into_balance(init_locked_sui), option::none(), ctx)
    }

    #[lint_allow(self_transfer)]
    public entry fun mint(tick_record: &mut TickRecordV2, ctx: &mut TxContext) {
        let ms = do_mint(tick_record, ctx);
        transfer::public_transfer(ms, tx_context::sender(ctx));
    }
    
    public fun do_mint(tick_record: &mut TickRecordV2, ctx: &mut TxContext): Movescription {
        let mint_get_factory = movescription::tick_record_borrow_mut_df<MintGetFactory, WITNESS>(tick_record, WITNESS{});
        assert!(mint_get_factory.init_locked_sui == 0 && mint_get_factory.init_locked_move == 0, ErrorInvalidMintFunction);
        internal_mint(tick_record, mint_get_factory.amount_per_mint, balance::zero<SUI>(), option::none(), ctx)
    }

    fun internal_mint(tick_record: &mut TickRecordV2, amount_per_mint: u64, init_locked_sui: Balance<SUI>, init_locked_move: Option<Movescription>, ctx: &mut TxContext): Movescription {
        let remain = movescription::tick_record_v2_remain(tick_record);
        let amount = if(remain < amount_per_mint){
            remain
        }else{
            amount_per_mint
        };
        let minted_movescription = movescription::do_mint_with_witness(tick_record, init_locked_sui, amount, option::none(), WITNESS{}, ctx);
        if(option::is_some(&init_locked_move)){
            movescription::lock_within(&mut minted_movescription, option::destroy_some(init_locked_move));
        }else{
            option::destroy_none(init_locked_move);
        };
        minted_movescription
    }

    // ======== MintGetFactory functions ========

    public fun amount_per_mint(tick_record: &TickRecordV2): u64 {
        let mint_get_factory = movescription::tick_record_borrow_df<MintGetFactory>(tick_record);
        mint_get_factory.amount_per_mint
    }

    public fun init_locked_sui(tick_record: &TickRecordV2): u64 {
        let mint_get_factory = movescription::tick_record_borrow_df<MintGetFactory>(tick_record);
        mint_get_factory.init_locked_sui
    }

    public fun init_locked_move(tick_record: &TickRecordV2): u64 {
        let mint_get_factory = movescription::tick_record_borrow_df<MintGetFactory>(tick_record);
        mint_get_factory.init_locked_move
    }
}