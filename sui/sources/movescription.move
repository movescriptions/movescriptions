module smartinscription::movescription {
    use std::ascii::{Self, string, String};
    use std::vector;
    use std::option::{Self, Option};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    //use sui::dynamic_field as df;
    use sui::tx_context::{Self, TxContext};
    use sui::event::emit;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::package;
    use sui::display;
    use smartinscription::string_util::{to_uppercase};
    use smartinscription::svg;


    // ======== Constants =========
    const VERSION: u64 = 2;
    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;
    const MAX_MINT_FEE: u64 = 100_000_000_000;
    const EPOCH_DURATION_MS: u64 = 60 * 1000;
    const MIN_EPOCHS: u64 = 60*2;
    const EPOCH_MAX_PLAYER: u64 = 500;
    const BASE_EPOCH_COUNT: u64 = 60*24*15;
    const BASE_TICK_LENGTH_FEE: u64 = 1000;
    const BASE_EPOCH_COUNT_FEE: u64 = 100;
    const PROTOCOL_TICK: vector<u8> = b"MOVE";
    const PROTOCOL_START_TIME_MS: u64 = 1704038400*1000;

    // ======== Errors =========
    const ErrorTickLengthInvaid: u64 = 1;
    const ErrorTickAlreadyExists: u64 = 2;
    const ErrorTickNotExists: u64 = 3;
    const ENotEnoughSupply: u64 = 4;
    const ENotEnoughToMint: u64 = 7;
    const EInvalidAmount: u64 = 9;
    const ENotSameTick: u64 = 10;
    //const EBalanceDONE: u64 = 11;
    const ETooHighFee: u64 = 12;
    //const EStillMinting: u64 = 13;
    const ENotStarted: u64 = 14;
    const EInvalidEpoch: u64 = 15;
    const EAttachCoinExists: u64 = 16;
    const EInvalidStartTime: u64 = 17;
    const ENotSameMetadata: u64 = 18;
    const EVersionMismatched: u64 = 19;
    const EDeprecatedFunction: u64 = 20;
    const EInvalidFeeTick: u64 = 21;
    const ENotEnoughDeployFee: u64 = 22;

    // ======== Types =========
    struct Movescription has key, store {
        id: UID,
        amount: u64,
        tick: String,
        /// The attachments coin count of the inscription.
        attach_coin: u64,
        acc: Balance<SUI>,
        // Add a metadata field for future extension
        metadata: Option<Metadata>,
    }

    #[allow(unused_field)]
    struct Metadata has store, copy, drop {
        /// The metadata content type, eg: image/png, image/jpeg, it is optional
        content_type: std::string::String,  
        /// The metadata content
        content: vector<u8>,
    }

    struct InscriptionBalance<phantom T> has copy, drop, store { }

    /// One-Time-Witness for the module.
    struct MOVESCRIPTION has drop {}

    struct DeployRecord has key {
        id: UID,
        version: u64,
        record: Table<String, address>,
    }

    struct EpochRecord has store {
        epoch: u64,
        start_time_ms: u64,
        players: vector<address>,
        mint_fees: Table<address, Balance<SUI>>,
    }

    struct TickRecord has key {
        id: UID,
        version: u64,
        tick: String,
        total_supply: u64,
        start_time_ms: u64,
        epoch_count: u64,
        current_epoch: u64,
        remain: u64,
        mint_fee: u64,
        epoch_records: Table<u64, EpochRecord>,
        current_supply: u64,
        total_transactions: u64,
    }

    // ======== Events =========
    struct DeployTick has copy, drop {
        id: ID,
        deployer: address,
        tick: String,
        total_supply: u64,
        start_time_ms: u64,
        epoch_count: u64,
        mint_fee: u64,
    }

    struct MintTick has copy, drop {
        sender: address,
        tick: String,
    }

    struct NewEpoch has copy, drop {
        tick: String,
        epoch: u64,
        start_time_ms: u64,
    }

    struct SettleEpoch has copy, drop {
        tick: String,
        epoch: u64,
        settle_user: address,
        settle_time_ms: u64,
        palyers_count: u64,
        epoch_amount: u64,
    }

    // ======== Functions =========
    fun init(otw: MOVESCRIPTION, ctx: &mut TxContext) {
        let deploy_record = DeployRecord { id: object::new(ctx), version: VERSION, record: table::new(ctx) };
        do_deploy(&mut deploy_record, PROTOCOL_TICK, 100_0000_0000, PROTOCOL_START_TIME_MS, 60*24*15, 100000000, ctx);
        transfer::share_object(deploy_record);
        let keys = vector[
            std::string::utf8(b"tick"),
            std::string::utf8(b"amount"),
            std::string::utf8(b"image_url"),
            std::string::utf8(b"project_url"),
        ];

        let p = b"mrc-20";
        let op = b"mint";
        let tick = b"{tick}";
        let amt = b"{amount}";

        let img_metadata = svg::generateSVG(p,op,tick,amt);

        let values = vector[
            std::string::utf8(b"{tick}"),
            std::string::utf8(b"{amount}"),
            std::string::utf8(img_metadata),
            std::string::utf8(b"https://movescriptions.org"),
        ];
        let publisher = package::claim(otw, ctx);
        let display = display::new_with_fields<Movescription>(
            &publisher, keys, values, ctx
        );
        display::update_version(&mut display);
        let deployer: address = tx_context::sender(ctx);
        transfer::public_transfer(publisher, deployer);
        transfer::public_transfer(display, deployer);
    }

    fun new_movescription(
        amount: u64,
        tick: String,
        fee_balance: Balance<SUI>,
        metadata: Option<Metadata>,
        ctx: &mut TxContext
    ): Movescription {
        Movescription {
            id: object::new(ctx),
            amount,
            tick,
            attach_coin: 0,
            acc: fee_balance,
            metadata,
        }
    }

    fun do_deploy(
        deploy_record: &mut DeployRecord, 
        tick: vector<u8>,
        total_supply: u64,
        start_time_ms: u64,
        epoch_count: u64,
        mint_fee: u64,
        ctx: &mut TxContext
    ) {
        to_uppercase(&mut tick);
        let tick_str: String = string(tick);
        let tick_len: u64 = ascii::length(&tick_str);
        assert!(MIN_TICK_LENGTH <= tick_len && tick_len <= MAX_TICK_LENGTH, ErrorTickLengthInvaid);
        assert!(!table::contains(&deploy_record.record, tick_str), ErrorTickAlreadyExists);
        assert!(total_supply > MIN_EPOCHS, ENotEnoughSupply);
        assert!(epoch_count >= MIN_EPOCHS, EInvalidEpoch);
        assert!(mint_fee <= MAX_MINT_FEE, ETooHighFee);
        
        let tick_uid = object::new(ctx);
        let tick_id = object::uid_to_inner(&tick_uid);
        let tick_record: TickRecord = TickRecord {
            id: tick_uid,
            version: VERSION,
            tick: tick_str,
            total_supply,
            start_time_ms,
            epoch_count,
            current_epoch: 0,
            remain: total_supply,
            mint_fee,
            epoch_records: table::new(ctx),
            current_supply: 0,
            total_transactions: 0,
        };
        let tk_record_address: address = object::id_address(&tick_record);
        table::add(&mut deploy_record.record, tick_str, tk_record_address);
        transfer::share_object(tick_record);
        emit(DeployTick {
            id: tick_id,
            deployer: tx_context::sender(ctx),
            tick: tick_str,
            total_supply,
            start_time_ms,
            epoch_count,
            mint_fee,
        });
    }

    #[lint_allow(self_transfer)]
    public entry fun deploy_v2(
        deploy_record: &mut DeployRecord,
        fee_tick_record: &mut TickRecord,
        fee_scription: &mut Movescription, 
        tick: vector<u8>,
        total_supply: u64,
        start_time_ms: u64,
        epoch_count: u64,
        mint_fee: u64,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(deploy_record.version <= VERSION, EVersionMismatched);
        let now_ms = clock::timestamp_ms(clk);
        if(start_time_ms == 0){
            start_time_ms = now_ms;
        };
        assert!(start_time_ms >= now_ms, EInvalidStartTime);
        assert!(fee_scription.tick == string(PROTOCOL_TICK), EInvalidFeeTick);
        assert!(fee_tick_record.tick == fee_scription.tick, EInvalidFeeTick);

        let deploy_fee_amount = calculate_deploy_fee(tick, epoch_count);
        assert!(fee_scription.amount >= deploy_fee_amount, ENotEnoughDeployFee);
        let deploy_fee = do_split(fee_scription, deploy_fee_amount, ctx);
        //Burn the fee and Return the acc SUI to the deployer
        let acc_in_deploy_fee = do_burn(fee_tick_record, deploy_fee, ctx);
        let deployer: address = tx_context::sender(ctx);
        transfer::public_transfer(acc_in_deploy_fee, deployer); 
        do_deploy(deploy_record, tick, total_supply, start_time_ms, epoch_count, mint_fee, ctx);
    }

    public entry fun deploy(
        _deploy_record: &mut DeployRecord, 
        _tick: vector<u8>,
        _total_supply: u64,
        _start_time_ms: u64,
        _epoch_count: u64,
        _mint_fee: u64,
        _clk: &Clock,
        _ctx: &mut TxContext
    ) {
        abort EDeprecatedFunction
    }

    #[lint_allow(self_transfer)]
    public fun do_mint(
        tick_record: &mut TickRecord,
        fee_coin: Coin<SUI>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tick_record.version <= VERSION, EVersionMismatched);
        assert!(tick_record.remain > 0, ENotEnoughToMint);
        let now_ms = clock::timestamp_ms(clk);
        assert!(now_ms >= tick_record.start_time_ms, ENotStarted);
        tick_record.total_transactions = tick_record.total_transactions + 1;

        let sender: address = tx_context::sender(ctx);
        let tick: String = tick_record.tick;

        let mint_fee_coin = if(coin::value<SUI>(&fee_coin) == tick_record.mint_fee){
            fee_coin
        }else{
            let mint_fee_coin = coin::split<SUI>(&mut fee_coin, tick_record.mint_fee, ctx);
            transfer::public_transfer(fee_coin, sender);
            mint_fee_coin
        };
        let fee_balance: Balance<SUI> = coin::into_balance<SUI>(mint_fee_coin);

        let current_epoch = tick_record.current_epoch;
        if (table::contains(&tick_record.epoch_records, current_epoch)){
            let epoch_record: &mut EpochRecord = table::borrow_mut(&mut tick_record.epoch_records, current_epoch);
            mint_in_epoch(epoch_record, sender, fee_balance);
            // If the epoch is over, we need to settle it and start a new epoch
            // If the epoch player is full, we do not wait and start a new epoch
            let epoch_player_len = vector::length(&epoch_record.players);
            if (epoch_record.start_time_ms + EPOCH_DURATION_MS < now_ms || epoch_player_len >= EPOCH_MAX_PLAYER) {
                settlement(tick_record, current_epoch, sender,  now_ms, ctx);
            };
        } else {
            let epoch_record = new_epoch_record(tick, current_epoch, now_ms, sender, fee_balance, ctx);
            table::add(&mut tick_record.epoch_records, current_epoch, epoch_record);
        };


        emit(MintTick {
            sender: sender,
            tick: tick,
        });
    }

    fun mint_in_epoch(epoch_record: &mut EpochRecord, sender: address, fee_balance: Balance<SUI>){
        if (!table::contains(&epoch_record.mint_fees, sender)) {
            vector::push_back(&mut epoch_record.players, sender);
            table::add(&mut epoch_record.mint_fees, sender, fee_balance);
        } else {
            let last_fee_balance: &mut Balance<SUI> = table::borrow_mut(&mut epoch_record.mint_fees, sender);
            balance::join(last_fee_balance, fee_balance);
        };
    }

    public entry fun mint(
        tick_record: &mut TickRecord,
        tick: vector<u8>,
        fee_coin: Coin<SUI>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        to_uppercase(&mut tick);
        let tick_str: String = string(tick);
        assert!(tick_record.tick == tick_str, ErrorTickNotExists);  // parallel optimization
        do_mint(tick_record, fee_coin, clk, ctx);
    }

    fun new_epoch_record(tick: String, epoch: u64, now_ms: u64, sender: address, fee_balance: Balance<SUI>, ctx: &mut TxContext) : EpochRecord{
        let mint_fees = table::new(ctx);
        table::add(&mut mint_fees, sender, fee_balance);
        emit(NewEpoch {
            tick,
            epoch,
            start_time_ms: now_ms,
        });
        EpochRecord {
            epoch,
            start_time_ms: now_ms,
            players: vector[sender],
            mint_fees,
        }
    }

    fun settlement(tick_record: &mut TickRecord, epoch: u64, settle_user: address, now_ms: u64, ctx: &mut TxContext) {
        let tick = tick_record.tick;
        let epoch_record: &mut EpochRecord = table::borrow_mut(&mut tick_record.epoch_records, epoch);
        let epoch_amount: u64 = tick_record.total_supply / tick_record.epoch_count;
        // include the remainder to the last epoch
        if (epoch_amount * 2 > tick_record.remain) {
            epoch_amount = tick_record.remain;
        };
        
        let players = epoch_record.players;
        let idx = 0;
        let players_len = vector::length(&players);
        
        let per_player_amount = epoch_amount / players_len;
        if (per_player_amount == 0) {
            per_player_amount = 1;
        };
        while (idx < players_len) {
            let player = *vector::borrow(&players, idx);
            let fee_balance: Balance<SUI> = table::remove(&mut epoch_record.mint_fees, player);
            if (tick_record.remain > 0) {
                let ins: Movescription = new_movescription(per_player_amount, tick, fee_balance, option::none(), ctx);
                transfer::public_transfer(ins, player);
                tick_record.remain = tick_record.remain - per_player_amount;
                tick_record.current_supply = tick_record.current_supply + per_player_amount;
            }else{
                // if the remain is 0, we should return the fee_balance to the player
                transfer::public_transfer(coin::from_balance<SUI>(fee_balance, ctx), player);
            };
            idx = idx + 1;
        };
        let real_epoch_amount = per_player_amount * players_len;
        if(real_epoch_amount < epoch_amount){
            // if the real_epoch_amount is less than epoch_amount, we send the remainder to the settle_user as a reward
            let remainder = epoch_amount - real_epoch_amount;
            let ins: Movescription = new_movescription(remainder, tick, balance::zero<SUI>(), option::none(), ctx);
            transfer::public_transfer(ins, settle_user);
            tick_record.remain = tick_record.remain - remainder;
            tick_record.current_supply = tick_record.current_supply + remainder;
        };
        // The mint_fees should be empty, this should not happen, add assert for debug
        // We can remove this assert after we are sure there is no bug
        assert!(table::is_empty(&epoch_record.mint_fees), 0);

        emit(SettleEpoch {
            tick,
            epoch,
            settle_user,
            settle_time_ms: now_ms,
            palyers_count: players_len,
            epoch_amount,
        });

        if (tick_record.remain != 0) {
            //start a new epoch
            let new_epoch = epoch + 1;
            // the settle_user is the first player in the new epoch, but the mint_fee belongs to the last epoch
            // it means the settle_user can free mint a new inscription as a reward
            let epoch_record = new_epoch_record(tick, new_epoch, now_ms, settle_user, balance::zero<SUI>(), ctx);
            table::add(&mut tick_record.epoch_records, new_epoch, epoch_record);
            tick_record.current_epoch = new_epoch;
        };
    }

    public entry fun merge(
        inscription1: &mut Movescription,
        inscription2: Movescription,
    ) {
        assert!(inscription1.tick == inscription2.tick, ENotSameTick);
        assert!(inscription2.attach_coin == 0, EAttachCoinExists);
        assert!(inscription1.metadata == inscription2.metadata, ENotSameMetadata);

        let Movescription { id, amount, tick: _, attach_coin:_, acc, metadata:_ } = inscription2;
        inscription1.amount = inscription1.amount + amount;
        balance::join<SUI>(&mut inscription1.acc, acc);
        object::delete(id);
    }

    public fun do_burn(
        tick_record: &mut TickRecord,
        inscription: Movescription,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        assert!(tick_record.version == VERSION, EVersionMismatched);
        assert!(inscription.attach_coin == 0, EAttachCoinExists);
        let Movescription { id, amount: amount, tick: _, attach_coin:_, acc, metadata:_ } = inscription;
        tick_record.current_supply = tick_record.current_supply - amount;
        let acc: Coin<SUI> = coin::from_balance<SUI>(acc, ctx);
        object::delete(id);
        acc
    }

    #[lint_allow(self_transfer)]
    public entry fun burn(
        tick_record: &mut TickRecord,
        inscription: Movescription,
        ctx: &mut TxContext
    ) {
        let acc = do_burn(tick_record, inscription, ctx);
        transfer::public_transfer(acc, tx_context::sender(ctx));
    }

    public fun do_split(
        inscription: &mut Movescription,
        amount: u64,
        ctx: &mut TxContext
    ) : Movescription {
        assert!(0 < amount && amount < inscription.amount, EInvalidAmount);
        let acc_amount = balance::value(&inscription.acc);
        let new_ins_fee_balance = if (acc_amount == 0) {
            balance::zero<SUI>()
        } else {
            let new_ins_acc_amount = split_acc(acc_amount, amount, inscription.amount);
            if (new_ins_acc_amount == 0) {
                new_ins_acc_amount = 1;
            };
            balance::split<SUI>(&mut inscription.acc, new_ins_acc_amount)
        };
        inscription.amount = inscription.amount - amount;
        new_movescription(
            amount, 
            inscription.tick,
            new_ins_fee_balance,
            inscription.metadata,
            ctx)
    }

    fun split_acc(acc_amount: u64, split_amount: u64, inscription_amount: u64): u64 {
        let new_acc_amount = ((((acc_amount as u128) * (split_amount as u128)) / (inscription_amount as u128)) as u64);
        if (new_acc_amount == 0) {
            new_acc_amount = 1;
        };
        new_acc_amount
    }

    #[lint_allow(self_transfer)]
    public entry fun split(
        inscription: &mut Movescription,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let ins = do_split(inscription, amount, ctx);
        transfer::public_transfer(ins, tx_context::sender(ctx));
    }

    // Interface reserved for future SFT transactions
    public fun inject_sui(inscription: &mut Movescription, receive: Coin<SUI>) {
        coin::put(&mut inscription.acc, receive);
    }

    public entry fun inject_sui_entry(inscription: &mut Movescription, receive: Coin<SUI>) {
        inject_sui(inscription, receive);
    }

    // ===== Migrate functions =====

    public fun migrate_deploy_record(deploy_record: &mut DeployRecord) {
        assert!(deploy_record.version <= VERSION, EVersionMismatched);
        deploy_record.version = VERSION;
    }

    public fun migrate_tick_record(tick_record: &mut TickRecord) {
        assert!(tick_record.version <= VERSION, EVersionMismatched);
        tick_record.version = VERSION;
    }

    // ======== Movescription Read Functions =========
    public fun amount(inscription: &Movescription): u64 {
        inscription.amount
    }

    public fun tick(inscription: &Movescription): String {
        inscription.tick
    }

    public fun attach_coin(inscription: &Movescription): u64 {
        inscription.attach_coin
    }

    public fun acc(inscription: &Movescription): u64 {
        balance::value(&inscription.acc)
    }

    // ======== TickRecord Read Functions =========
    public fun tick_record_total_supply(tick_record: &TickRecord): u64 {
        tick_record.total_supply
    }

    public fun tick_record_start_time_ms(tick_record: &TickRecord): u64 {
        tick_record.start_time_ms
    }

    public fun tick_record_epoch_count(tick_record: &TickRecord): u64 {
        tick_record.epoch_count
    }

    public fun tick_record_current_epoch(tick_record: &TickRecord): u64 {
        tick_record.current_epoch
    }

    public fun tick_record_remain(tick_record: &TickRecord): u64 {
        tick_record.remain
    }

    public fun tick_record_mint_fee(tick_record: &TickRecord): u64 {
        tick_record.mint_fee
    }

    public fun tick_record_current_supply(tick_record: &TickRecord): u64 {
        tick_record.current_supply
    }

    public fun tick_record_total_transactions(tick_record: &TickRecord): u64 {
        tick_record.total_transactions
    }

    // ======== Constants functions =========

    public fun epoch_duration_ms(): u64 {
        EPOCH_DURATION_MS
    }

    public fun min_epochs(): u64 {
        MIN_EPOCHS
    }

    public fun epoch_max_player(): u64 {
        EPOCH_MAX_PLAYER
    }

    public fun protocol_tick(): vector<u8> {
        PROTOCOL_TICK
    }

    public fun protocol_start_time_ms(): u64 {
        PROTOCOL_START_TIME_MS
    }

    public fun calculate_deploy_fee(tick: vector<u8>, epoch_count: u64): u64 {
        assert!(epoch_count >= MIN_EPOCHS, EInvalidEpoch);
        let tick_len: u64 = ascii::length(&string(tick));
        assert!(tick_len >= MIN_TICK_LENGTH && tick_len <= MAX_TICK_LENGTH, ErrorTickLengthInvaid);
        let tick_len_fee =  BASE_TICK_LENGTH_FEE * MIN_TICK_LENGTH/tick_len;
        let epoch_fee = if(epoch_count >= BASE_EPOCH_COUNT){
            BASE_EPOCH_COUNT_FEE
        }else{
            BASE_EPOCH_COUNT * BASE_EPOCH_COUNT_FEE / epoch_count
        };
        tick_len_fee + epoch_fee
    }

    // ========= Test Functions =========

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(MOVESCRIPTION{}, ctx);
    }

    #[test]
    fun test_split_acc(){
        let acc_amount = 1000u64;
        let split_amount = 100u64;
        let inscription_amount = 1000u64;
        let new_acc_amount = split_acc(acc_amount, split_amount, inscription_amount);
        assert!(new_acc_amount == 100u64, 0);
    }

    #[test]
    fun test_split_acc2(){
        let acc_amount = 4_0000_0000u64;
        let split_amount = 1111_1111u64;
        let inscription_amount = 9999_9999u64;
        let new_acc_amount = split_acc(acc_amount, split_amount, inscription_amount);
        //std::debug::print(&new_acc_amount);
        assert!(new_acc_amount == 4444_4444u64, 0);
    }

    #[test]
    fun test_split_acc3(){
        let acc_amount = 100u64;
        let split_amount = 1u64;
        let inscription_amount = 100_0000u64;
        let new_acc_amount = split_acc(acc_amount, split_amount, inscription_amount);
        //std::debug::print(&new_acc_amount);
        assert!(new_acc_amount == 1u64, 0);
    }

    #[test]
    fun test_calculate_deploy_fee(){
        let fee = calculate_deploy_fee(b"MOVE", BASE_EPOCH_COUNT);
        assert!(fee == 1100, 0);
        let fee = calculate_deploy_fee(b"MOVER", BASE_EPOCH_COUNT);
        assert!(fee == 900, 0);
        let fee = calculate_deploy_fee(b"MMMMMMMMMMMMMMMMMMMMMMMMMMMMOVER", BASE_EPOCH_COUNT);
        assert!(fee == 225, 0);
        let fee = calculate_deploy_fee(b"MOVE", 60*24);
        //std::debug::print(&fee);
        assert!(fee == 2500, 0);
        let fee = calculate_deploy_fee(b"MOVE", MIN_EPOCHS);
        assert!(fee == 19000, 0); 
        //std::debug::print(&fee);
    }
}