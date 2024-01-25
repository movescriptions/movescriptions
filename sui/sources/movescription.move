module smartinscription::movescription {
    use std::ascii::{Self, string, String};
    use std::vector;
    use std::option::{Self, Option};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event::emit;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::sui::SUI;
    use sui::clock::{Clock};
    use sui::package;
    use sui::display;
    use sui::dynamic_field as df;
    use smartinscription::string_util::{to_uppercase};
    use smartinscription::svg;
    use smartinscription::type_util;
    use smartinscription::tick_name;

    friend smartinscription::tick_factory;
    friend smartinscription::epoch_bus_factory;

    // ======== Constants =========
    const VERSION: u64 = 3;
    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;
    //const MAX_MINT_FEE: u64 = 100_000_000_000;
    const EPOCH_DURATION_MS: u64 = 60 * 1000;
    const MIN_EPOCHS: u64 = 60*2;
    const EPOCH_MAX_PLAYER: u64 = 500;
    const BASE_EPOCH_COUNT: u64 = 60*24*15;
    const BASE_TICK_LENGTH_FEE: u64 = 1000;
    const BASE_EPOCH_COUNT_FEE: u64 = 100;
    const PROTOCOL_START_TIME_MS: u64 = 1704038400*1000;
    const PROTOCOL_TICK_TOTAL_SUPPLY: u64 = 100_0000_0000;
    
    // ======== Errors =========
    const ErrorTickLengthInvaid: u64 = 1;
    const ErrorTickAlreadyExists: u64 = 2;
    //const ErrorTickNotExists: u64 = 3;
    const ENotEnoughSupply: u64 = 4;
    const ENotEnoughToMint: u64 = 7;
    const EInvalidAmount: u64 = 9;
    const ENotSameTick: u64 = 10;
    //const EBalanceDONE: u64 = 11;
    //const ETooHighFee: u64 = 12;
    //const EStillMinting: u64 = 13;
    //const ENotStarted: u64 = 14;
    const EInvalidEpoch: u64 = 15;
    const EAttachDFExists: u64 = 16;
    //const EInvalidStartTime: u64 = 17;
    const ENotSameMetadata: u64 = 18;
    const EVersionMismatched: u64 = 19;
    const EDeprecatedFunction: u64 = 20;
    //const EInvalidFeeTick: u64 = 21;
    //const ENotEnoughDeployFee: u64 = 22;
    //const ETemporarilyDisabled: u64 = 23;
    const ErrorNotWitness: u64 = 24;
    const ErrorUnexpectedTick: u64 = 25;

    // ======== Types =========
    struct Movescription has key, store {
        id: UID,
        /// The inscription amount
        amount: u64,
        /// The inscription tick, it is an ascii string with length between 4 and 32
        /// The tick is always uppercase, and unique in the protocol
        tick: String,
        /// The attachment dynamic fields count of the inscription.
        /// For historical reasons, this field is named `attach_coin`, it should be `attach_df`
        attach_coin: u64,
        /// The locked SUI in the inscription
        /// Because the locked SUI can be injected after the inscription is created, it like an accumulator.
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
        /// The Tick name -> TickRecord object id
        record: Table<String, address>,
    }

    #[allow(unused_field)]
    struct EpochRecord has store {
        epoch: u64,
        start_time_ms: u64,
        players: vector<address>,
        mint_fees: Table<address, Balance<SUI>>,
    }

    #[allow(unused_field)]
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

    struct TickStat has store{
        /// The remaining inscription amount not minted
        remain: u64,
        /// The current supply of the inscription, burn will decrease the current supply
        current_supply: u64,
        /// Total mint transactions
        total_transactions: u64, 
    }

    struct TickRecordV2 has key, store {
        id: UID,
        version: u64,
        tick: String,
        total_supply: u64,
        // The mint factory type name
        mint_factory: String,
        stat: TickStat,
    }

    struct BurnReceipt has key, store {
        id: UID,
        tick: String,
        amount: u64,
    }

    // ======== Events =========
    #[allow(unused_field)]
    struct DeployTick has copy, drop {
        id: ID,
        deployer: address,
        tick: String,
        total_supply: u64,
        start_time_ms: u64,
        epoch_count: u64,
        mint_fee: u64,
    }

    struct DeployTickV2 has copy, drop {
        id: ID,
        deployer: address,
        tick: String,
        total_supply: u64,
    }

    struct MintTick has copy, drop {
        sender: address,
        tick: String,
    }

    struct BurnTick has copy, drop {
        sender: address,
        tick: String,
        amount: u64,
        message: std::string::String,
    }

    #[allow(unused_field)]
    struct NewEpoch has copy, drop {
        tick: String,
        epoch: u64,
        start_time_ms: u64,
    }

    #[allow(unused_field)]
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
        // The original version auto deploy `MOVE` in this init function
        // after refactor, the new version deploy `MOVE` in epoch_bus_factory
        //do_deploy(&mut deploy_record, protocol_tick(), 100_0000_0000, PROTOCOL_START_TIME_MS, 60*24*15, 100000000, ctx);
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
        acc_balance: Balance<SUI>,
        metadata: Option<Metadata>,
        ctx: &mut TxContext
    ): Movescription {
        Movescription {
            id: object::new(ctx),
            amount,
            tick,
            attach_coin: 0,
            acc: acc_balance,
            metadata,
        }
    }

    #[lint_allow(self_transfer)]
    public entry fun deploy_v2(
        _deploy_record: &mut DeployRecord,
        _fee_tick_record: &mut TickRecord,
        _fee_scription: &mut Movescription, 
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

    public fun do_mint(
        _tick_record: &mut TickRecord,
        _fee_coin: Coin<SUI>,
        _clk: &Clock,
        _ctx: &mut TxContext
    ) {
        abort EDeprecatedFunction
    }


    public entry fun mint(
        _tick_record: &mut TickRecord,
        _tick: vector<u8>,
        _fee_coin: Coin<SUI>,
        _clk: &Clock,
        _ctx: &mut TxContext
    ) {
        abort EDeprecatedFunction
    }

    #[lint_allow(self_transfer)]
    public fun do_deploy_with_witness<W: drop>(
        deploy_record: &mut DeployRecord, 
        tick_name: Movescription,
        total_supply: u64,
        _witness: W,
        ctx: &mut TxContext
    ) : TickRecordV2 {
        assert_protocol_tick_name_tick(&tick_name);
        let Movescription { id, amount: _, tick: _, attach_coin:_, acc, metadata } = tick_name;
        object::delete(id);
        //TODO charge deploy fee
        let acc_coin = coin::from_balance<SUI>(acc, ctx);
        transfer::public_transfer(acc_coin, tx_context::sender(ctx));
        let metadata = option::destroy_some(metadata);
        let tick = ascii::string(metadata.content);
        internal_deploy_with_witness(deploy_record, tick, total_supply, _witness, ctx)
    }

    public(friend) fun internal_deploy_with_witness<W: drop>(
        deploy_record: &mut DeployRecord, 
        tick: String,
        total_supply: u64,
        _witness: W,
        ctx: &mut TxContext
    ) : TickRecordV2 {
        assert!(!table::contains(&deploy_record.record, tick), ErrorTickAlreadyExists);
        assert!(total_supply > 0, ENotEnoughSupply);
        assert!(type_util::is_witness<W>(), ErrorNotWitness);

        let mint_factory = type_util::module_id<W>();
        let tick_uid = object::new(ctx);
        let tick_id = object::uid_to_inner(&tick_uid);
        let tick_record: TickRecordV2 = TickRecordV2 {
            id: tick_uid,
            version: VERSION,
            tick: tick,
            total_supply,
            mint_factory,
            stat: TickStat {
                remain: total_supply,
                current_supply: 0,
                total_transactions: 0,
            },
        };
        let tk_record_address: address = object::id_address(&tick_record);
        table::add(&mut deploy_record.record, tick, tk_record_address);
        emit(DeployTickV2 {
            id: tick_id,
            deployer: tx_context::sender(ctx),
            tick: tick,
            total_supply,
        });
        tick_record
    }

    #[lint_allow(self_transfer)]
    public fun do_mint_with_witness<W: drop>(
        tick_record: &mut TickRecordV2,
        init_locked_asset: Balance<SUI>,
        amount: u64,
        metadata: Option<Metadata>,
        _witness: W,
        ctx: &mut TxContext
    ) : Movescription {
        assert!(tick_record.version <= VERSION, EVersionMismatched);
        assert!(tick_record.stat.remain > 0,  ENotEnoughToMint);
        assert!(tick_record.stat.remain >= amount, ENotEnoughToMint);
        assert!(type_util::is_witness<W>(), ErrorNotWitness);
        type_util::assert_witness<W>(tick_record.mint_factory);

        tick_record.stat.remain = tick_record.stat.remain - amount;
        tick_record.stat.current_supply = tick_record.stat.current_supply + amount;
        tick_record.stat.total_transactions = tick_record.stat.total_transactions + 1;

        let tick: String = tick_record.tick;
        let sender = tx_context::sender(ctx);
        emit(MintTick{
            sender,
            tick, 
        });
        new_movescription(amount, tick, init_locked_asset, metadata, ctx)
    }

    public fun is_mergeable(inscription1: &Movescription, inscription2: &Movescription): bool {
        inscription1.tick == inscription2.tick && inscription1.metadata == inscription2.metadata
    }

    public fun do_merge(
        inscription1: &mut Movescription,
        inscription2: Movescription,
    ) {
        assert!(inscription1.tick == inscription2.tick, ENotSameTick);
        assert!(inscription2.attach_coin == 0, EAttachDFExists);
        assert!(inscription1.metadata == inscription2.metadata, ENotSameMetadata);

        let Movescription { id, amount, tick: _, attach_coin:_, acc, metadata:_ } = inscription2;
        inscription1.amount = inscription1.amount + amount;
        balance::join<SUI>(&mut inscription1.acc, acc);
        object::delete(id);
    }

    public entry fun merge(
        inscription1: &mut Movescription,
        inscription2: Movescription,
    ) {
        do_merge(inscription1, inscription2);
    }

    /// Burn inscription and return the acc SUI, without message and BurnRecipt
    public fun do_burn(
        tick_record: &mut TickRecord,
        inscription: Movescription,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        do_burn_with_message(tick_record, inscription, vector::empty(), ctx)
    }

    /// Burn Movescription without BurnRecipt
    public fun do_burn_with_message(
        tick_record: &mut TickRecord,
        inscription: Movescription,
        message: vector<u8>,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        assert!(tick_record.version <= VERSION, EVersionMismatched);
        assert!(tick_record.tick == inscription.tick, ENotSameTick);
        assert!(inscription.attach_coin == 0, EAttachDFExists);
        let Movescription { id, amount: amount, tick: tick, attach_coin:_, acc, metadata:_ } = inscription;
        tick_record.current_supply = tick_record.current_supply - amount;
        let acc: Coin<SUI> = coin::from_balance<SUI>(acc, ctx);
        object::delete(id);

        emit({
            BurnTick {
                sender: tx_context::sender(ctx),
                tick: tick,
                amount: amount,                
                message: std::string::utf8(message),
            }
        });

        acc
    }

    /// Burn Movescription without BurnRecipt
    public fun do_burn_with_message_v2(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,
        message: vector<u8>,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        assert!(tick_record.version <= VERSION, EVersionMismatched);
        assert!(tick_record.tick == inscription.tick, ENotSameTick);
        assert!(inscription.attach_coin == 0, EAttachDFExists);
        let Movescription { id, amount: amount, tick: tick, attach_coin:_, acc, metadata:_ } = inscription;
        tick_record.stat.current_supply = tick_record.stat.current_supply - amount;
        let acc: Coin<SUI> = coin::from_balance<SUI>(acc, ctx);
        object::delete(id);

        emit({
            BurnTick {
                sender: tx_context::sender(ctx),
                tick: tick,
                amount: amount,                
                message: std::string::utf8(message),
            }
        });

        acc
    }

    public fun do_burn_for_receipt(
        tick_record: &mut TickRecord,
        inscription: Movescription,        
        message: vector<u8>,
        ctx: &mut TxContext
    ) : (Coin<SUI>, BurnReceipt) {
        let tick = inscription.tick;
        let amount = inscription.amount;
        let acc = do_burn_with_message(tick_record, inscription, message, ctx);

        let receipt = BurnReceipt {
            id: object::new(ctx),
            tick: tick,
            amount: amount,
        };
        
        (acc, receipt)
    }

    public fun do_burn_for_receipt_v2(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,        
        message: vector<u8>,
        ctx: &mut TxContext
    ) : (Coin<SUI>, BurnReceipt) {
        let tick = inscription.tick;
        let amount = inscription.amount;
        let acc = do_burn_with_message_v2(tick_record, inscription, message, ctx);

        let receipt = BurnReceipt {
            id: object::new(ctx),
            tick: tick,
            amount: amount,
        };
        
        (acc, receipt)
    }

    /// Drop the BurnReceipt, allow developer to drop the receipt after the receipt is used
    public fun drop_receipt(receipt: BurnReceipt):(String, u64) {
        let BurnReceipt { id, tick: tick, amount: amount } = receipt;
        object::delete(id);
        (tick, amount)
    }

    #[lint_allow(self_transfer)]
    /// Burn inscription and return the acc SUI to the sender
    public entry fun burn(
        tick_record: &mut TickRecord,
        inscription: Movescription,
        ctx: &mut TxContext
    ) {
        let acc = do_burn_with_message(tick_record, inscription, vector::empty(), ctx);
        transfer::public_transfer(acc, tx_context::sender(ctx));
    }

    #[lint_allow(self_transfer)]
    /// Burn inscription and return the acc SUI to the sender, and got a BurnReceipt Movescription
    public entry fun burn_for_receipt(
        tick_record: &mut TickRecord,
        inscription: Movescription,        
        message: vector<u8>,
        ctx: &mut TxContext
    ) {
        let (acc, receipt) = do_burn_for_receipt(tick_record, inscription, message, ctx);
        transfer::public_transfer(acc, tx_context::sender(ctx));
        transfer::public_transfer(receipt, tx_context::sender(ctx));
    }

      #[lint_allow(self_transfer)]
    /// Burn inscription and return the acc SUI to the sender, and got a BurnReceipt Movescription
    public entry fun burn_for_receipt_v2(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,        
        message: vector<u8>,
        ctx: &mut TxContext
    ) {
        let (acc, receipt) = do_burn_for_receipt_v2(tick_record, inscription, message, ctx);
        transfer::public_transfer(acc, tx_context::sender(ctx));
        transfer::public_transfer(receipt, tx_context::sender(ctx));
    }
    
    public fun is_splitable(inscription: &Movescription): bool {
        inscription.amount > 1 && inscription.attach_coin == 0
    }

    public fun do_split(
        inscription: &mut Movescription,
        amount: u64,
        ctx: &mut TxContext
    ) : Movescription {
        assert!(0 < amount && amount < inscription.amount, EInvalidAmount);
        assert!(inscription.attach_coin == 0, EAttachDFExists);
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

    // Interface for SFT transactions
    public fun inject_sui(inscription: &mut Movescription, receive: Coin<SUI>) {
        coin::put(&mut inscription.acc, receive);
    }

    public entry fun inject_sui_entry(inscription: &mut Movescription, receive: Coin<SUI>) {
        inject_sui(inscription, receive);
    }

    // ===== check tick util functions =====

    /// Assert the tick of Movescription is protocol tick `MOVE`
    public fun assert_protocol_tick(ms: &Movescription) {
        assert!(ascii::into_bytes(ms.tick) == tick_name::protocol_tick(), ErrorUnexpectedTick);
    }

    /// Assert the tick of Movescription is protocol tick name tick `TICK`
    public fun assert_protocol_tick_name_tick(ms: &Movescription) {
        assert!(ascii::into_bytes(ms.tick) == tick_name::protocol_tick_name_tick(), ErrorUnexpectedTick);
    }
    
    /// Assert the tick of Movescription is protocol tick name service tick `NAME`
    public fun assert_protocol_name_service_tick(ms: &Movescription) {
        assert!(ascii::into_bytes(ms.tick) == tick_name::protocol_name_service_tick(), ErrorUnexpectedTick);
    }

    public fun assert_tick(ms: &Movescription, tick: vector<u8>) {
        assert!(check_tick(ms, tick), ErrorUnexpectedTick);
    }

    public fun assert_tick_record(tick_record: &TickRecordV2, tick: vector<u8>) {
        assert!(check_tick_record(tick_record, tick), ErrorUnexpectedTick);
    }

    // Security by check tick
    public fun check_tick(ms: &Movescription, tick: vector<u8>): bool {
        to_uppercase(&mut tick);
        ascii::into_bytes(ms.tick) == tick
    }

    public fun check_tick_record(tick_record: &TickRecordV2, tick: vector<u8>): bool {
        to_uppercase(&mut tick);
        ascii::into_bytes(tick_record.tick) == tick
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

    public fun metadata(inscription: &Movescription): Option<Metadata> {
        inscription.metadata
    }

    // ======== DeployRecord Read Functions =========

    public fun is_deployed(deploy_record: &DeployRecord, tick: vector<u8>): bool {
        to_uppercase(&mut tick);
        let tick_str: String = string(tick);
        table::contains(&deploy_record.record, tick_str)
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

    // ======= TickRecordV2 Read Functions ========

    public fun tick_record_v2_tick(tick_record: &TickRecordV2): String {
        tick_record.tick
    }

    public fun tick_record_v2_total_supply(tick_record: &TickRecordV2): u64 {
        tick_record.total_supply
    }

    public fun tick_record_v2_mint_factory(tick_record: &TickRecordV2): String {
        tick_record.mint_factory
    }

    public fun tick_record_v2_remain(tick_record: &TickRecordV2): u64 {
        tick_record.stat.remain
    }

    public fun tick_record_v2_current_supply(tick_record: &TickRecordV2): u64 {
        tick_record.stat.current_supply
    }   

    public fun tick_record_v2_total_transactions(tick_record: &TickRecordV2): u64 {
        tick_record.stat.total_transactions
    }

    // ======== TickRecordV2 df functions =========

    public fun tick_record_add_df<V: store, W: drop>(tick_record: &mut TickRecordV2, value: V, _witness: W) {
        type_util::assert_witness<W>(tick_record.mint_factory);
        let name = type_util::type_to_name<V>();
        df::add(&mut tick_record.id, name, value);
    }

    public fun tick_record_remove_df<V: store, W: drop>(tick_record: &mut TickRecordV2, _witness: W) : V {
        type_util::assert_witness<W>(tick_record.mint_factory);
        let name = type_util::type_to_name<V>();
        df::remove(&mut tick_record.id, name)
    }

    public fun tick_record_borrow_mut_df<V: store, W: drop>(tick_record: &mut TickRecordV2, _witness: W) : &mut V {
        type_util::assert_witness<W>(tick_record.mint_factory);
        let name = type_util::type_to_name<V>();
        df::borrow_mut(&mut tick_record.id, name)
    }

    public fun tick_record_borrow_df<V: store>(tick_record: &TickRecordV2) : &V{
        let name = type_util::type_to_name<V>();
        df::borrow(&tick_record.id, name) 
    }

    /// Returns 
    public fun tick_record_exists_df<V: store>(tick_record: &TickRecordV2) : bool {
        let name = type_util::type_to_name<V>();
        df::exists_with_type<String, V>(&tick_record.id, name) 
    }

    // ======== Metadata Functions =========

    public fun new_metadata(content_type: std::string::String, content: vector<u8>) : Metadata {
        Metadata {
            content_type,
            content,
        }
    }
    
    public fun metadata_content_type(metadata: &Metadata): std::string::String {
        metadata.content_type
    }

    public fun metadata_content(metadata: &Metadata): vector<u8> {
        metadata.content
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
        tick_name::protocol_tick()
    }

    public fun protocol_start_time_ms(): u64 {
        PROTOCOL_START_TIME_MS
    }

    public fun protocol_tick_total_supply(): u64{
        PROTOCOL_TICK_TOTAL_SUPPLY
    }

    public fun base_epoch_count(): u64 {
        BASE_EPOCH_COUNT
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

    #[test_only]
    public fun deploy_with_witness_for_testing<W: drop>(
        deploy_record: &mut DeployRecord,
        tick: String,
        total_supply: u64,
        witness: W,
        ctx: &mut TxContext
    ) : TickRecordV2 {
        internal_deploy_with_witness(deploy_record, tick, total_supply, witness, ctx)
    }

    #[test_only]
    public fun new_movescription_for_testing(
        amount: u64,
        tick: String,
        acc_balance: Balance<SUI>,
        metadata: Option<Metadata>,
        ctx: &mut TxContext
    ) : Movescription {
        new_movescription(amount, tick, acc_balance, metadata, ctx)
    }

    #[test_only]
    public fun drop_movescription_for_testing(inscription: Movescription) {
        let Movescription { id, amount: _, tick: _, attach_coin:_, acc, metadata:_ } = inscription;
        balance::destroy_for_testing(acc);
        object::delete(id);
    } 
}