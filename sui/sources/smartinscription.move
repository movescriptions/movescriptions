module smartinscription::inscription {
    use std::ascii::{Self, string, String};
    use std::option::Option;
    use std::vector;
    use sui::object::{Self, UID};
    use sui::transfer::{Self, Receiving};
    use sui::dynamic_field as df;
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


    // ======== Constants =========
    const VERSION: u64 = 1;
    //const FIVE_SECONDS_IN_MS: u64 = 5_000;
    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;
    //const MAX_MINT_TIMES: u64 = 100_000_000;
    //const MIN_MINT_TIMES: u64 = 10_000;
    const MAX_MINT_FEE: u64 = 10_000_000_000;
    const EPOCH_DURATION_MS: u64 = 60 * 1000;
    const MIN_EPOCHS: u64 = 60*2;

    // ======== Errors =========
    const ErrorTickLengthInvaid: u64 = 1;
    const ErrorTickAlreadyExists: u64 = 2;
    const ErrorTickNotExists: u64 = 3;
    const ENotEnoughSupply: u64 = 4;
    //const EInappropriateMintTimes: u64 = 5;
    //const EOverMaxPerMint: u64 = 6;
    const ENotEnoughToMint: u64 = 7;
    //const EMintTooFrequently: u64 = 8;
    const EInvalidAmount: u64 = 9;
    const ENotSameTick: u64 = 10;
    const EBalanceDONE: u64 = 11;
    const ETooHighFee: u64 = 12;
    const EStillMinting: u64 = 13;
    const ENotStarted: u64 = 14;
    const EInvalidEpoch: u64 = 15;
    const EAttachCoinExists: u64 = 16;
    const EInvalidStartTime: u64 = 17;

    // ======== Types =========
    struct Inscription has key, store {
        id: UID,
        amount: u64,
        tick: String,
        image_url: Option<std::string::String>,
        /// The attachments coin count of the inscription.
        attach_coin: u64,
        acc: Balance<SUI>,
    }

    struct InscriptionBalance<phantom T> has copy, drop, store { }

    /// One-Time-Witness for the module.
    struct INSCRIPTION has drop {}

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
        image_url: Option<std::string::String>,
        epoch_records: Table<u64, EpochRecord>,
        current_supply: u64,
        total_transactions: u64,
    }

    struct ImgCap has key, store {
        id: UID,
    }

    // ======== Events =========
    struct DeployTick has copy, drop {
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
    fun init(otw: INSCRIPTION, ctx: &mut TxContext) {
        let deploy_record = DeployRecord { id: object::new(ctx), version: VERSION, record: table::new(ctx) };
        do_deploy(&mut deploy_record, b"MOVE", 100_0000_0000, 1704038400*1000, 60*24*15, 100000000, b"", ctx);
        transfer::share_object(deploy_record);
        let keys = vector[
            std::string::utf8(b"tick"),
            std::string::utf8(b"amount"),
            std::string::utf8(b"image_url"),
            std::string::utf8(b"description"),
            std::string::utf8(b"project_url"),
        ];

        let values = vector[
            std::string::utf8(b"{tick}"),
            std::string::utf8(b"{amount}"),
            std::string::utf8(b"{image_url}"),
            std::string::utf8(b"MoveInscription of the Sui ecosystem!"),
            std::string::utf8(b"https://"),
        ];
        let publisher = package::claim(otw, ctx);
        let display = display::new_with_fields<Inscription>(
            &publisher, keys, values, ctx
        );
        display::update_version(&mut display);
        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));

        let img_cap = ImgCap { id: object::new(ctx) };
        transfer::public_transfer(img_cap, tx_context::sender(ctx));
    }

    fun do_deploy(
        deploy_record: &mut DeployRecord, 
        tick: vector<u8>,
        total_supply: u64,
        start_time_ms: u64,
        epoch_count: u64,
        mint_fee: u64,
        image_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        to_uppercase(&mut tick);
        let tick_str: String = string(tick);
        let tick_len: u64 = ascii::length(&tick_str);
        assert!(MIN_TICK_LENGTH <= tick_len && tick_len <= MAX_TICK_LENGTH, ErrorTickLengthInvaid);
        assert!(!table::contains(&deploy_record.record, tick_str), ErrorTickAlreadyExists);
        assert!(total_supply > MIN_EPOCHS, ENotEnoughSupply);
        assert!(epoch_count >= MIN_EPOCHS, EInvalidEpoch);
        
        //TODO should we limit the max mint fee?
        assert!(mint_fee <= MAX_MINT_FEE, ETooHighFee);
        let tick_record: TickRecord = TickRecord {
            id: object::new(ctx),
            version: VERSION,
            tick: tick_str,
            total_supply,
            start_time_ms,
            epoch_count,
            current_epoch: 0,
            remain: total_supply,
            mint_fee,
            image_url: std::string::try_utf8(image_url),
            epoch_records: table::new(ctx),
            current_supply: 0,
            total_transactions: 0,
        };
        let tk_record_address: address = object::id_address(&tick_record);
        table::add(&mut deploy_record.record, tick_str, tk_record_address);
        transfer::share_object(tick_record);
        emit(DeployTick {
            deployer: tx_context::sender(ctx),
            tick: tick_str,
            total_supply,
            start_time_ms,
            epoch_count,
            mint_fee,
        });
    }

    public entry fun deploy(
        deploy_record: &mut DeployRecord, 
        tick: vector<u8>,
        total_supply: u64,
        start_time_ms: u64,
        epoch_count: u64,
        mint_fee: u64,
        image_url: vector<u8>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        let now_ms = clock::timestamp_ms(clk);
        if(start_time_ms == 0){
            start_time_ms = now_ms;
        };
        assert!(start_time_ms >= now_ms, EInvalidStartTime); 
        do_deploy(deploy_record, tick, total_supply, start_time_ms, epoch_count, mint_fee, image_url, ctx);
    }

    #[lint_allow(self_transfer)]
    public fun do_mint(
        tick_record: &mut TickRecord,
        fee_coin: Coin<SUI>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
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
            // if the epoch is over, we need to settle it and start a new epoch
            if(epoch_record.start_time_ms + EPOCH_DURATION_MS < now_ms){
                settlement(tick_record, current_epoch, sender,  now_ms, ctx);
            };
        }else{
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

    /// Mint by transfer SUI to the TickRecord Object
    public fun mint_by_transfer(tick_record: &mut TickRecord, sent: Receiving<Coin<SUI>>, ctx: &mut TxContext) {
        std::debug::print(&string(b"mint_by_transfer"));
        assert!(tick_record.remain > 0, ENotEnoughToMint);
        let sender: address = tx_context::sender(ctx); 
        let coin = transfer::public_receive(&mut tick_record.id, sent);
        assert!(coin::value<SUI>(&coin) == tick_record.mint_fee, ETooHighFee);
        let current_epoch = tick_record.current_epoch;
        assert!(table::contains(&tick_record.epoch_records, current_epoch), ENotStarted);
        
        tick_record.total_transactions = tick_record.total_transactions + 1;
        let epoch_record: &mut EpochRecord = table::borrow_mut(&mut tick_record.epoch_records, current_epoch);
        mint_in_epoch(epoch_record, sender, coin::into_balance<SUI>(coin));
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
        let epoch_amount = tick_record.total_supply / tick_record.epoch_count;
        
        if (epoch_amount > tick_record.remain) {
            epoch_amount = tick_record.remain;
        };
        
        let players = epoch_record.players;
        let idx = 0;
        let players_len = vector::length(&players);
        
        let per_player_amount = epoch_amount / players_len;
        if(per_player_amount == 0){
            per_player_amount = 1;
        };
        while (idx < players_len) {
            let player = *vector::borrow(&players, idx);
            let fee_balance: Balance<SUI> = table::remove(&mut epoch_record.mint_fees, player);
            if (tick_record.remain > 0) {
                let ins: Inscription = new_inscription(
                per_player_amount, tick, tick_record.image_url, fee_balance, ctx
                );
                transfer::public_transfer(ins, player);
                tick_record.remain = tick_record.remain - per_player_amount;
                tick_record.current_supply = tick_record.current_supply + per_player_amount;
            }else{
                // if the remain is 0, we should return the fee_balance to the player
                transfer::public_transfer(coin::from_balance<SUI>(fee_balance, ctx), player);
            };
            idx = idx + 1;
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

    fun new_inscription(
        amount: u64,
        tick: String,
        image_url: Option<std::string::String>,
        fee_balance: Balance<SUI>,
        ctx: &mut TxContext
    ): Inscription {
        Inscription {
            id: object::new(ctx),
            amount,
            tick,
            image_url,
            attach_coin: 0,
            acc: fee_balance,
        }
    }

    public entry fun merge(
        inscription1: &mut Inscription,
        inscription2: Inscription,
    ) {
        assert!(inscription1.tick == inscription2.tick, ENotSameTick);
        assert!(inscription2.attach_coin == 0, EAttachCoinExists);

        let Inscription { id, amount, tick: _, attach_coin:_, image_url: _, acc } = inscription2;
        inscription1.amount = inscription1.amount + amount;
        balance::join<SUI>(&mut inscription1.acc, acc);
        object::delete(id);
    }

    public fun do_burn(
        tick_record: &mut TickRecord,
        inscription: Inscription,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        assert!(inscription.attach_coin == 0, EAttachCoinExists);
        let Inscription { id, amount: amount, tick: _, attach_coin:_, image_url: _, acc } = inscription;
        tick_record.current_supply = tick_record.current_supply - amount;
        let acc: Coin<SUI> = coin::from_balance<SUI>(acc, ctx);
        object::delete(id);
        acc
    }

    #[lint_allow(self_transfer)]
    public entry fun burn(
        tick_record: &mut TickRecord,
        inscription: Inscription,
        ctx: &mut TxContext
    ) {
        let acc = do_burn(tick_record, inscription, ctx);
        transfer::public_transfer(acc, tx_context::sender(ctx));
    }

    public fun do_split(
        inscription: &mut Inscription,
        amount: u64,
        ctx: &mut TxContext
    ) : Inscription {
        assert!(0 < amount && amount < inscription.amount, EInvalidAmount);
        inscription.amount = inscription.amount - amount;
        let fee_balance_amount = balance::value(&inscription.acc);
        let new_ins_fee_balance = if(fee_balance_amount == 0){
            balance::zero<SUI>()
        }else{
            let new_ins_fee_balance_amount = (fee_balance_amount*amount)/inscription.amount;
            if(new_ins_fee_balance_amount == 0){
                new_ins_fee_balance_amount = 1;
            };
            balance::split<SUI>(&mut inscription.acc, new_ins_fee_balance_amount)
        };
        let ins: Inscription = new_inscription(
            amount, 
            inscription.tick,
            inscription.image_url,
            new_ins_fee_balance,
            ctx);
        ins
    }

    #[lint_allow(self_transfer)]
    public entry fun split(
        inscription: &mut Inscription,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let ins = do_split(inscription, amount, ctx);
        transfer::public_transfer(ins, tx_context::sender(ctx));
    }

    public fun inject_sui(inscription: &mut Inscription, receive: Coin<SUI>) {
        coin::put(&mut inscription.acc, receive);
    }

    public fun accept_coin<T>(inscription: &mut Inscription, sent: Receiving<Coin<T>>) {
        let coin = transfer::public_receive(&mut inscription.id, sent);
        let inscription_balance_type = InscriptionBalance<T>{};
        let inscription_uid = &mut inscription.id;

        if (df::exists_(inscription_uid, inscription_balance_type)) {
            let balance: &mut Coin<T> = df::borrow_mut(inscription_uid, inscription_balance_type);
            coin::join(balance, coin);
        } else {
            inscription.attach_coin = inscription.attach_coin + 1;
            df::add(inscription_uid, inscription_balance_type, coin);
        }
    }

    public fun withdraw_all<T>(inscription: &mut Inscription): Coin<T> {
        let inscription_balance_type = InscriptionBalance<T>{};
        let inscription_uid = &mut inscription.id;
        assert!(df::exists_(inscription_uid, inscription_balance_type), EBalanceDONE);
        inscription.attach_coin = inscription.attach_coin - 1;
        let return_coin: Coin<T> = df::remove(inscription_uid, inscription_balance_type);
        return_coin
    }

    public fun clean_epoch_records(tick_record: &mut TickRecord, _holder: address) {
        assert!(tick_record.remain == 0, EStillMinting);
        //TODO
        //table::remove(&mut tick_record.epoch_records, holder);
    }

    public entry fun set_image_url(_: &ImgCap, tick_record: &mut TickRecord, image_url: vector<u8>) {
        tick_record.image_url = std::string::try_utf8(image_url);
    }

    public entry fun update_image_url(tick_record: &TickRecord, inscription: &mut Inscription) {
        assert!(tick_record.tick == inscription.tick, ENotSameTick);
        inscription.tick = tick_record.tick;
    }

    // ======== Inscription Read Functions =========
    public fun amount(inscription: &Inscription): u64 {
        inscription.amount
    }

    public fun tick(inscription: &Inscription): String {
        inscription.tick
    }

    public fun attach_coin(inscription: &Inscription): u64 {
        inscription.attach_coin
    }

    public fun acc(inscription: &Inscription): u64 {
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

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(INSCRIPTION{}, ctx);
    }

}