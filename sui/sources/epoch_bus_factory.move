module smartinscription::epoch_bus_factory{
    use std::ascii::{Self, String};
    use std::vector;
    use std::option;
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::event::emit;
    use smartinscription::movescription::{Self, Movescription, DeployRecord, TickRecordV2};
    use smartinscription::tick_name;
    use smartinscription::tick_factory;
    use smartinscription::assert_util;

    friend smartinscription::init;

    const EPOCH_DURATION_MS: u64 = 60 * 1000;
    const MIN_EPOCHS: u64 = 60*2;
    const EPOCH_MAX_PLAYER: u64 = 500;

    const ErrorEpochNotStarted: u64 = 1;
    const ErrorInvalidEpoch: u64 = 2;

    struct EpochRecord has store {
        epoch: u64,
        start_time_ms: u64,
        players: vector<address>,
        locked_assets: Table<address, Balance<SUI>>,
    }

    struct NewEpochEvent has copy, drop {
        tick: String,
        epoch: u64,
        start_time_ms: u64,
    }

    struct SettleEpochEvent has copy, drop {
        tick: String,
        epoch: u64,
        settle_user: address,
        settle_time_ms: u64,
        palyers_count: u64,
        epoch_supply: u64,
    }

    struct EpochBusFactory has store {
        init_locked_asset: u64,
        start_time_ms: u64,
        epoch_count: u64,
        epoch_amount: u64,
        current_epoch: u64,
        epoch_records: Table<u64, EpochRecord>,
    }

    struct WITNESS has drop {}


    /// Deploy `MOVE` tick
    /// The original version deploy MOVE in the `movescription::init` function
    /// This version do not affect the origin version on mainnet. 
    public fun deploy_move_tick(
        deploy_record: &mut DeployRecord, 
        ctx: &mut TxContext) {
        let tick = tick_name::move_tick();
        if(movescription::is_deployed(deploy_record, tick)){
            return
        };
        let total_supply = movescription::move_tick_total_supply();
        let init_locked_asset = 100000000; //0.1sui
        let epoch_count = 60*24*15;
        let tick_record = movescription::internal_deploy_with_witness(deploy_record, ascii::string(tick), total_supply, true, WITNESS{}, ctx);
        after_deploy(tick_record, total_supply, init_locked_asset, movescription::protocol_start_time_ms(), epoch_count, ctx);
    }
    
    /// Deploy the `tick_name` movescription by epoch_bus_factory
    public fun do_deploy(
        deploy_record: &mut DeployRecord,
        tick_tick_record: &mut TickRecordV2, 
        tick_name: Movescription,
        total_supply: u64,
        init_locked_asset: u64,
        start_time_ms: u64,
        epoch_count: u64, 
        clock: &Clock,
        ctx: &mut TxContext) {
        assert_util::assert_tick_tick(&tick_name);
        assert!(epoch_count >= MIN_EPOCHS, ErrorInvalidEpoch);
        
        let tick_record = tick_factory::do_deploy(deploy_record, tick_tick_record, tick_name, total_supply, true, WITNESS{}, clock, ctx);
        after_deploy(tick_record, total_supply, init_locked_asset, start_time_ms, epoch_count, ctx);
    }

    #[lint_allow(share_owned)]
    fun after_deploy(
        tick_record: TickRecordV2,
        total_supply: u64,
        init_locked_asset: u64,
        start_time_ms: u64,
        epoch_count: u64, ctx: &mut TxContext) {
        let factory = EpochBusFactory{
            init_locked_asset,
            start_time_ms,
            epoch_count,
            epoch_amount: total_supply / epoch_count,
            current_epoch: 0,
            epoch_records: table::new(ctx),
        };
        movescription::tick_record_add_df(&mut tick_record, factory, WITNESS{});
        transfer::public_share_object(tick_record);
    }

    #[lint_allow(self_transfer)]
    public fun do_mint(
        tick_record: &mut TickRecordV2,
        init_locked_coin: Coin<SUI>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        let now_ms = clock::timestamp_ms(clk);
        let tick: String = movescription::tick_record_v2_tick(tick_record);

        let factory = movescription::tick_record_borrow_mut_df<EpochBusFactory, WITNESS>(tick_record, WITNESS{});
        assert!(now_ms >= factory.start_time_ms, ErrorEpochNotStarted);

        let sender: address = tx_context::sender(ctx);
        
        let init_locked_asset = factory.init_locked_asset;
        let acc_coin = if(coin::value<SUI>(&init_locked_coin) == init_locked_asset){
            init_locked_coin
        }else{
            let acc_coin = coin::split<SUI>(&mut init_locked_coin, init_locked_asset, ctx);
            transfer::public_transfer(init_locked_coin, sender);
            acc_coin
        };
        let acc_balance: Balance<SUI> = coin::into_balance<SUI>(acc_coin);

        let current_epoch = factory.current_epoch;
        if (table::contains(&factory.epoch_records, current_epoch)){
            let epoch_record: &mut EpochRecord = table::borrow_mut(&mut factory.epoch_records, current_epoch);
            mint_in_epoch(epoch_record, sender, acc_balance);
            // If the epoch is over, we need to settle it and start a new epoch
            // If the epoch player is full, we do not wait and start a new epoch
            let epoch_player_len = vector::length(&epoch_record.players);
            if (epoch_record.start_time_ms + EPOCH_DURATION_MS < now_ms || epoch_player_len >= EPOCH_MAX_PLAYER) {
                settlement(tick_record, current_epoch, sender,  now_ms, ctx);
            };
        } else {
            let epoch_record = new_epoch_record(tick, current_epoch, now_ms, sender, acc_balance, ctx);
            table::add(&mut factory.epoch_records, current_epoch, epoch_record);
        };


    }

    fun mint_in_epoch(epoch_record: &mut EpochRecord, sender: address, acc_balance: Balance<SUI>){
        if (!table::contains(&epoch_record.locked_assets, sender)) {
            vector::push_back(&mut epoch_record.players, sender);
            table::add(&mut epoch_record.locked_assets, sender, acc_balance);
        } else {
            let last_fee_balance: &mut Balance<SUI> = table::borrow_mut(&mut epoch_record.locked_assets, sender);
            balance::join(last_fee_balance, acc_balance);
        };
    }

    fun new_epoch_record(tick: String, epoch: u64, now_ms: u64, sender: address, acc_balance: Balance<SUI>, ctx: &mut TxContext) : EpochRecord{
        let locked_assets = table::new(ctx);
        table::add(&mut locked_assets, sender, acc_balance);
        emit(NewEpochEvent {
            tick,
            epoch,
            start_time_ms: now_ms,
        });
        EpochRecord {
            epoch,
            start_time_ms: now_ms,
            players: vector[sender],
            locked_assets,
        }
    }

    fun settlement(tick_record: &mut TickRecordV2, epoch: u64, settle_user: address, now_ms: u64, ctx: &mut TxContext) {
        let remain = movescription::tick_record_v2_remain(tick_record);
        let tick = movescription::tick_record_v2_tick(tick_record);
        let factory = movescription::tick_record_remove_df<EpochBusFactory, WITNESS>(tick_record, WITNESS{});
        let epoch_amount: u64 = factory.epoch_amount;
        let epoch_record: &mut EpochRecord = table::borrow_mut(&mut factory.epoch_records, epoch);
        
        // include the remainder to the last epoch
        if (epoch_amount * 2 > remain) {
            epoch_amount = remain;
        };
        let epoch_supply = 0;
        let players = epoch_record.players;
        let idx = 0;
        let players_len = vector::length(&players);
        
        let per_player_amount = epoch_amount / players_len;
        if (per_player_amount == 0) {
            per_player_amount = 1;
        };
        while (idx < players_len) {
            let player = *vector::borrow(&players, idx);
            let acc_balance: Balance<SUI> = table::remove(&mut epoch_record.locked_assets, player);
            if (remain > 0) {
                let ins: Movescription = internal_mint(tick_record, per_player_amount, acc_balance, ctx);
                transfer::public_transfer(ins, player);
                remain = remain - per_player_amount;
                epoch_supply = epoch_supply + per_player_amount;
            }else{
                // if the remain is 0, we should return the acc_balance to the player
                transfer::public_transfer(coin::from_balance<SUI>(acc_balance, ctx), player);
            };
            idx = idx + 1;
        };
        let real_epoch_amount = per_player_amount * players_len;
        if(real_epoch_amount < epoch_amount){
            // if the real_epoch_amount is less than epoch_amount, we send the remainder to the settle_user as a reward
            let remainder = epoch_amount - real_epoch_amount;
            let ins: Movescription = internal_mint(tick_record, remainder, balance::zero<SUI>(), ctx);
            transfer::public_transfer(ins, settle_user);
            remain = remain - remainder;
            epoch_supply = epoch_supply + remainder;
        };
        // The locked_assets should be empty, this should not happen, add assert for debug
        // We can remove this assert after we are sure there is no bug
        assert!(table::is_empty(&epoch_record.locked_assets), 0);

        emit(SettleEpochEvent {
            tick,
            epoch,
            settle_user,
            settle_time_ms: now_ms,
            palyers_count: players_len,
            epoch_supply,
        });

        if (remain != 0) {
            //start a new epoch
            let new_epoch = epoch + 1;
            // the settle_user is the first player in the new epoch, but the mint_fee belongs to the last epoch
            // it means the settle_user can free mint a new inscription as a reward
            let epoch_record = new_epoch_record(tick, new_epoch, now_ms, settle_user, balance::zero<SUI>(), ctx);
            table::add(&mut factory.epoch_records, new_epoch, epoch_record);
            factory.current_epoch = new_epoch;
        };
        movescription::tick_record_add_df(tick_record, factory, WITNESS{});
    }

    fun internal_mint(tick_record: &mut TickRecordV2, amount: u64, acc_balance: Balance<SUI>, ctx: &mut TxContext): Movescription {
        movescription::do_mint_with_witness(tick_record, acc_balance, amount, option::none(), WITNESS{}, ctx)
    }

    // ======= Testing functions =========
    #[test_only]
    public fun mint_for_testing(tick_record: &mut TickRecordV2, amount: u64, acc_balance: Balance<SUI>, ctx: &mut TxContext) : Movescription {
        internal_mint(tick_record, amount, acc_balance, ctx)
    }
}