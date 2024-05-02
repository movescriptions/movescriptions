module smartinscription::movescription {
    use std::ascii::{Self, string, String};
    use std::vector;
    use std::option::{Self, Option};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event::emit;
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::sui::SUI;
    use sui::clock::{Clock};
    use sui::package::{Self, Publisher};
    use sui::display;
    use sui::dynamic_field as df;
    use sui_system::staking_pool::StakedSui;
    use sui_system::sui_system::{request_add_stake_non_entry, SuiSystemState, request_withdraw_stake_non_entry};
    use smartinscription::string_util::{to_uppercase};
    use smartinscription::svg;
    use smartinscription::type_util::{Self, type_to_name};
    use smartinscription::tick_name;

    friend smartinscription::name_factory;
    friend smartinscription::tick_factory;
    friend smartinscription::epoch_bus_factory;
    friend smartinscription::init;
    friend smartinscription::mint_get_factory;
    friend smartinscription::movescription_to_amm;


    // ======== Constants =========
    const VERSION: u64 = 4;
    const PROTOCOL_START_TIME_MS: u64 = 1704038400*1000;
    const MOVE_TICK_TOTAL_SUPPLY: u64 = 100_0000_0000;
    const TREASURY_FIELD_NAME: vector<u8> = b"treasury";
    const INCENTIVE_FIELD_NAME: vector<u8> = b"incentive";
    const BURN_TO_COIN_FIELD_NAME: vector<u8> = b"burn_to_coin";
    const MCOIN_DECIMALS: u8 = 9;
    const MCOIN_DECIMALS_BASE: u64 = 1_000_000_000;
    
    // ======== Errors =========
    const ErrorTickAlreadyExists: u64 = 2;
    const ErrorNotEnoughSupply: u64 = 4;
    const ErrorNotEnoughToMint: u64 = 7;
    const EInvalidAmount: u64 = 9;
    const ErrorNotSameTick: u64 = 10;
    const ErrorAttachDFExists: u64 = 16;
    const ErrorNotSameMetadata: u64 = 18;
    const ErrorVersionMismatched: u64 = 19;
    const ErrorDeprecatedFunction: u64 = 20;
    const ErrorNotWitness: u64 = 24;
    const ErrorCanNotBurnByOwner: u64 = 26;
    const ErrorNotZero: u64 = 27;
    const ErrorInvalidCoinType: u64 = 28;
    const ErrorTreasuryAlreadyInit: u64 = 29;
    const ErrorNotEnoughBalance: u64 = 30;

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

    struct Metadata has store, copy, drop {
        /// The metadata content type, eg: image/png, image/jpeg, it is optional
        content_type: std::string::String,  
        /// The metadata content
        content: vector<u8>,
    }

    struct LockedBox has store{
        locked_movescription: Movescription,
    }

    /// One-Time-Witness for the module.
    struct MOVESCRIPTION has drop {}

    struct DeployRecord has key {
        id: UID,
        version: u64,
        /// The Tick name -> TickRecord object id
        record: Table<String, address>,
    }

    struct TickStat has store, copy, drop {
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
        /// The movescription can be burned by the owner 
        burnable: bool,
        /// The mint factory type name
        mint_factory: String,
        stat: TickStat,
    }

    struct BurnReceipt has key, store {
        id: UID,
        tick: String,
        amount: u64,
    }

    struct Treasury<phantom T> has store{
        cap: TreasuryCap<T>,
        coin_type: String,
    }

    struct InitTreasuryArgs<phantom T> has key, store{
        id: UID,
        tick: String,
        cap: Option<TreasuryCap<T>>,
    }

    // ======== Events =========
   
    struct DeployTickV2 has copy, drop {
        id: ID,
        deployer: address,
        tick: String,
        total_supply: u64,
        burnable: bool,
    }

    struct MintTickV2 has copy, drop {
        id: ID, 
        sender: address,
        tick: String,
        amount: u64, 
    }

    struct BurnTick has copy, drop {
        sender: address,
        tick: String,
        amount: u64,
        message: std::string::String,
    }

    struct IncentiveEvent has copy, drop{
        to_mint_value: u64,
        new_burn_to_coin: u64,
    }

    // ======== Functions =========
    fun init(otw: MOVESCRIPTION, ctx: &mut TxContext) {
        let deploy_record = DeployRecord { id: object::new(ctx), version: VERSION, record: table::new(ctx) };
        transfer::share_object(deploy_record);

        // The original version auto deploy `MOVE` in this init function
        // after refactor, the new version deploy `MOVE` in epoch_bus_factory
        //do_deploy(&mut deploy_record, protocol_tick(), 100_0000_0000, PROTOCOL_START_TIME_MS, 60*24*15, 100000000, ctx);
        
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

    // === Deploy and Mint functions ===

    public(friend) fun internal_deploy_with_witness<W: drop>(
        deploy_record: &mut DeployRecord, 
        tick: String,
        total_supply: u64,
        burnable: bool,
        _witness: W,
        ctx: &mut TxContext
    ) : TickRecordV2 {
        assert!(!table::contains(&deploy_record.record, tick), ErrorTickAlreadyExists);
        assert!(total_supply > 0, ErrorNotEnoughSupply);
        assert!(type_util::is_witness<W>(), ErrorNotWitness);

        let mint_factory = type_util::module_id<W>();
        let tick_uid = object::new(ctx);
        let tick_id = object::uid_to_inner(&tick_uid);
        let tick_record: TickRecordV2 = TickRecordV2 {
            id: tick_uid,
            version: VERSION,
            tick: tick,
            total_supply,
            burnable,
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
            burnable,
        });
        tick_record
    }

    #[lint_allow(self_transfer)]
    public fun do_mint_with_witness<W: drop>(
        tick_record: &mut TickRecordV2,
        init_locked_sui: Balance<SUI>,
        amount: u64,
        metadata: Option<Metadata>,
        _witness: W,
        ctx: &mut TxContext
    ) : Movescription {
        assert!(tick_record.version <= VERSION, ErrorVersionMismatched);
        assert!(tick_record.stat.remain > 0,  ErrorNotEnoughToMint);
        assert!(tick_record.stat.remain >= amount, ErrorNotEnoughToMint);
        assert!(type_util::is_witness<W>(), ErrorNotWitness);
        type_util::assert_witness<W>(tick_record.mint_factory);

        tick_record.stat.remain = tick_record.stat.remain - amount;
        tick_record.stat.current_supply = tick_record.stat.current_supply + amount;
        tick_record.stat.total_transactions = tick_record.stat.total_transactions + 1;

        let tick: String = tick_record.tick;
        let sender = tx_context::sender(ctx);
        let movescription = new_movescription(amount, tick, init_locked_sui, metadata, ctx);
        emit(MintTickV2 {
            id: object::id(&movescription),
            sender,
            tick,
            amount,
        });
        movescription
    }

    // ======= Merge functions ========

    public fun is_mergeable(inscription1: &Movescription, inscription2: &Movescription): bool {
        inscription1.tick == inscription2.tick && inscription1.metadata == inscription2.metadata
    }

    public fun do_merge(
        inscription1: &mut Movescription,
        inscription2: Movescription,
    ) {
        assert!(inscription1.tick == inscription2.tick, ErrorNotSameTick);
        assert!(inscription2.attach_coin == 0, ErrorAttachDFExists);
        assert!(inscription1.metadata == inscription2.metadata, ErrorNotSameMetadata);
        if (contains_locked(&inscription2)) {
            let locked_movescription = unlock_box(&mut inscription2);
            lock_within(inscription1, locked_movescription);
        };
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

     // ======= Split functions ========
    
    /// Check if the inscription can be split
    public fun is_splitable(inscription: &Movescription): bool {
        inscription.amount > 1 && inscription.attach_coin == 0
    }

    /// Split the inscription and return the new inscription
    public fun do_split(
        inscription: &mut Movescription,
        amount: u64,
        ctx: &mut TxContext
    ) : Movescription {
        assert!(0 < amount && amount < inscription.amount, EInvalidAmount);
        assert!(inscription.attach_coin == 0, ErrorAttachDFExists);
        let acc_amount = balance::value(&inscription.acc);
        let original_amount = inscription.amount;
        let new_ins_fee_balance = if (acc_amount == 0) {
            balance::zero<SUI>()
        } else {
            let new_acc_amount = split_amount(acc_amount, amount, original_amount);
            balance::split<SUI>(&mut inscription.acc, new_acc_amount)
        };
        inscription.amount = original_amount - amount;

        let split_movescription = new_movescription(
            amount, 
            inscription.tick,
            new_ins_fee_balance,
            inscription.metadata,
            ctx);

        if(contains_locked(inscription)){
            let locked_movescription = borrow_mut_locked(inscription);
            let locked_split_amount = split_amount(locked_movescription.amount, amount, original_amount);
            let new_locked_movescription = do_split(locked_movescription, locked_split_amount, ctx);
            lock_within(&mut split_movescription, new_locked_movescription); 
        };
        split_movescription
    }

    fun split_amount(target_amount: u64, split_amount: u64, inscription_amount: u64): u64 {
        let new_split_amount = ((((target_amount as u128) * (split_amount as u128)) / (inscription_amount as u128)) as u64);
        if (new_split_amount == 0) {
            new_split_amount = 1;
        };
        new_split_amount
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

    // ========= Destroy and Burn functions =========

    public fun zero(tick_record: &TickRecordV2, ctx: &mut TxContext) : Movescription{
        new_movescription(0, tick_record.tick, balance::zero<SUI>(), option::none(), ctx)
    }

    public fun is_zero(self: &Movescription): bool {
        if(self.amount != 0 || self.attach_coin != 0 || balance::value(&self.acc) != 0 || option::is_some(&self.metadata)){
            return false
        };
        if(contains_locked(self)){
            let locked_movescription = borrow_locked(self);
            return is_zero(locked_movescription)
        };
        true
    }

    public fun destroy_zero(self: Movescription) {
        assert!(self.amount == 0, ErrorNotZero);
        assert!(self.attach_coin == 0, ErrorAttachDFExists);
        assert!(balance::value(&self.acc) == 0, ErrorNotZero);
        assert!(option::is_none(&self.metadata), ErrorNotZero);

        if(contains_locked(&self)){
            let locked_movescription = unlock_box(&mut self);
            destroy_zero(locked_movescription);
        };
        let Movescription { id, amount: _, tick: _, attach_coin:_, acc, metadata:_ } = self;
        balance::destroy_zero(acc);
        object::delete(id);
    }

    public fun do_burn_v2(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,
        ctx: &mut TxContext
    ) : (Coin<SUI>, Option<Movescription>) {
        do_burn_with_message_v2(tick_record, inscription, vector::empty(), ctx)
    }

    public fun do_burn_with_witness<W: drop>(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,
        message: vector<u8>,
        _witness: W,
        ctx: &mut TxContext
    ) : (Coin<SUI>, Option<Movescription>) {
        type_util::assert_witness<W>(tick_record.mint_factory);
        internal_burn(tick_record, inscription, message, ctx)
    }

    /// Burn Movescription without BurnRecipt
    public fun do_burn_with_message_v2(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,
        message: vector<u8>,
        ctx: &mut TxContext
    ) : (Coin<SUI>, Option<Movescription>) {
        assert!(tick_record.burnable, ErrorCanNotBurnByOwner);
        internal_burn(tick_record, inscription, message, ctx)
    }

    fun internal_burn(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,
        message: vector<u8>,
        ctx: &mut TxContext
    ) : (Coin<SUI>, Option<Movescription>) {
        assert!(tick_record.version <= VERSION, ErrorVersionMismatched);
        assert!(tick_record.tick == inscription.tick, ErrorNotSameTick);
        assert!(inscription.attach_coin == 0, ErrorAttachDFExists);
        let locked_movescription = if(contains_locked(&inscription)){
            option::some(unlock_box(&mut inscription))
        }else{
            option::none()
        };
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

        (acc,locked_movescription)
    }

    public fun do_burn_for_receipt_v2(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,        
        message: vector<u8>,
        ctx: &mut TxContext
    ) : (Coin<SUI>, Option<Movescription>, BurnReceipt) {
        let tick = inscription.tick;
        let amount = inscription.amount;
        let (acc, locked_movescription) = do_burn_with_message_v2(tick_record, inscription, message, ctx);

        let receipt = BurnReceipt {
            id: object::new(ctx),
            tick: tick,
            amount: amount,
        };
        
        (acc, locked_movescription, receipt)
    }

    #[lint_allow(self_transfer)]
    /// Burn inscription and return the acc SUI to the sender, and got a BurnReceipt Movescription
    public entry fun burn_for_receipt_v2(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,        
        message: vector<u8>,
        ctx: &mut TxContext
    ) {
        let (acc, locked_movescription, receipt) = do_burn_for_receipt_v2(tick_record, inscription, message, ctx);
        if(option::is_some(&locked_movescription)){
            let locked_movescription = option::destroy_some(locked_movescription);
            transfer::public_transfer(locked_movescription, tx_context::sender(ctx));
        }else{
            option::destroy_none(locked_movescription);
        };
        transfer::public_transfer(acc, tx_context::sender(ctx));
        transfer::public_transfer(receipt, tx_context::sender(ctx));
    }

    #[lint_allow(self_transfer)]
    public entry fun burn_v2(
        tick_record: &mut TickRecordV2,
        inscription: Movescription,
        ctx: &mut TxContext
    ) {
        let (acc, locked_movescription) = do_burn_v2(tick_record, inscription, ctx);
        if(option::is_some(&locked_movescription)){
            let locked_movescription = option::destroy_some(locked_movescription);
            transfer::public_transfer(locked_movescription, tx_context::sender(ctx));
        }else{
            option::destroy_none(locked_movescription);
        };
        transfer::public_transfer(acc, tx_context::sender(ctx));
    }

     /// Drop the BurnReceipt, allow developer to drop the receipt after the receipt is used
    public fun drop_receipt(receipt: BurnReceipt):(String, u64) {
        let BurnReceipt { id, tick: tick, amount: amount } = receipt;
        object::delete(id);
        (tick, amount)
    }

    // Interface for SFT transactions
    public fun inject_sui(inscription: &mut Movescription, receive: Coin<SUI>) {
        coin::put(&mut inscription.acc, receive);
    }

    public entry fun inject_sui_entry(inscription: &mut Movescription, receive: Coin<SUI>) {
        inject_sui(inscription, receive);
    }

    // ===== Treasury functions =====

    fun add_treasury<T: drop>(tick_record: &mut TickRecordV2, treasury: Treasury<T>){
        df::add(&mut tick_record.id, TREASURY_FIELD_NAME, treasury);
    }

    fun borrow_mut_treasury<T: drop>(tick_record: &mut TickRecordV2) : &mut Treasury<T> {
        df::borrow_mut(&mut tick_record.id, TREASURY_FIELD_NAME)
    }

    fun borrow_treasury<T: drop>(tick_record: &TickRecordV2) : &Treasury<T> {
        df::borrow(&tick_record.id, TREASURY_FIELD_NAME)
    }

    public fun is_treasury_inited(tick_record: &TickRecordV2): bool{
        df::exists_(&tick_record.id, TREASURY_FIELD_NAME)
    }

    public fun check_coin_type<T: drop>(tick_record: &TickRecordV2): bool{
        let treasury = borrow_treasury<T>(tick_record);
        let type_name = type_util::type_to_name<T>();
        type_name == treasury.coin_type
    }

    public fun coin_supply<T: drop>(tick_record: &TickRecordV2): u64{
        let treasury = borrow_treasury<T>(tick_record);
        coin::total_supply(&treasury.cap)
    }

    #[lint_allow(share_owned)]
    public fun new_init_treasury_args<T: drop>(
        tick: String,
        cap: TreasuryCap<T>, 
        coin_metadata: CoinMetadata<T>, 
        ctx: &mut TxContext
    ): InitTreasuryArgs<T> {
        //let struct_name = type_util::struct_name<T>();
        //assert!(tick == struct_name, ErrorInvalidCoinType);
        assert!(coin::get_symbol(&coin_metadata) == tick, ErrorInvalidCoinType);
        assert!(coin::total_supply(&cap) == 0, ErrorNotZero);
        assert!(coin::get_decimals(&coin_metadata) == MCOIN_DECIMALS, ErrorInvalidCoinType);
        transfer::public_share_object(coin_metadata);
        InitTreasuryArgs {
            id: object::new(ctx),
            tick: tick,
            cap: option::some(cap),
        }
    }

    //TODO we should delete the InitTreasuryArgs after init treasury, but the SUI mainnet is not support delete the shared object now
    public fun init_treasury<T: drop>(
        tick_record: &mut TickRecordV2, 
        init_args: &mut InitTreasuryArgs<T>
    ) {
        assert!(tick_record.version <= VERSION, ErrorVersionMismatched);
        assert!(!df::exists_(&tick_record.id, TREASURY_FIELD_NAME), ErrorTreasuryAlreadyInit);
        assert!(tick_record.tick == init_args.tick, ErrorNotSameTick);
        let cap = option::extract(&mut init_args.cap);
        let type_name = type_util::type_to_name<T>();
        let treasury = Treasury { cap, coin_type: type_name };
        add_treasury(tick_record, treasury);
    }

    public(friend) fun movescription_to_coin<T: drop>(
        tick_record: &mut TickRecordV2, 
        movescription: Movescription
    ): (Balance<SUI>, Option<Movescription>, Option<Metadata>, Balance<T>) {
        assert!(tick_record.version <= VERSION, ErrorVersionMismatched);
        assert!(tick_record.tick == movescription.tick, ErrorNotSameTick);
        assert!(movescription.attach_coin == 0, ErrorAttachDFExists);
    
        let locked_movescription = if(contains_locked(&movescription)){
            option::some(unlock_box(&mut movescription))
        }else{
            option::none()
        };
        let Movescription { id, amount: amount, tick: _, attach_coin:_, acc, metadata:metadata } = movescription;
        object::delete(id);
        let treasury = borrow_mut_treasury<T>(tick_record);
        let coin_amount = amount * MCOIN_DECIMALS_BASE;
        let balance_t = coin::mint_balance(&mut treasury.cap, coin_amount);
        (acc, locked_movescription, metadata, balance_t) 
    }

    public(friend) fun coin_to_movescription<T: drop>(
        tick_record: &mut TickRecordV2, 
        acc: Balance<SUI>, 
        locked: Option<Movescription>, 
        metadata: Option<Metadata>, 
        balance_t: Balance<T>, 
        ctx: &mut TxContext
    ): (Movescription, Balance<T>) {
        assert!(tick_record.version <= VERSION, ErrorVersionMismatched);
        let treasury = borrow_mut_treasury<T>(tick_record);
        let coin_amount = balance::value(&balance_t);
        assert!(coin_amount >= MCOIN_DECIMALS_BASE, ErrorNotEnoughBalance);
        let movescription_amount = coin_amount / MCOIN_DECIMALS_BASE;
        let decrease_balance = balance::split(&mut balance_t, movescription_amount * MCOIN_DECIMALS_BASE);
        coin::burn(&mut treasury.cap, coin::from_balance(decrease_balance, ctx));
        let movescription = new_movescription(movescription_amount, tick_record.tick, acc, metadata, ctx);
        if(option::is_some(&locked)){
            let locked = option::destroy_some(locked);
            lock_within(&mut movescription, locked);
        }else{
            option::destroy_none(locked);
        };
        (movescription, balance_t)
    }

    // ===== Treasury functions =====
    public fun add_incentive<T: drop>(
        tick_record: &mut TickRecordV2
    ) {
        assert!(tick_record.version <= VERSION, ErrorVersionMismatched);

        if (!df::exists_<vector<u8>>(&tick_record.id, BURN_TO_COIN_FIELD_NAME)) {
            df::add(&mut tick_record.id, BURN_TO_COIN_FIELD_NAME, 0);
        };
        let burn_amount = tick_record_v2_burned_amount(tick_record);
        let burn_to_coin = df::borrow_mut(&mut tick_record.id, BURN_TO_COIN_FIELD_NAME);
        let burn_value = burn_amount * MCOIN_DECIMALS_BASE;
        let to_mint_value = burn_value - *burn_to_coin;  // will abort if burn_value < burn_to_coin
        *burn_to_coin = *burn_to_coin + to_mint_value;
        let new_burn_to_coin = *burn_to_coin;
        let treasury = borrow_mut_treasury<T>(tick_record);
        let incentive_balance = coin::mint_balance(&mut treasury.cap, to_mint_value);
        emit(IncentiveEvent {
            to_mint_value: to_mint_value,
            new_burn_to_coin,
        });
        if (!df::exists_<vector<u8>>(&tick_record.id, INCENTIVE_FIELD_NAME)) {
            df::add(&mut tick_record.id, INCENTIVE_FIELD_NAME, incentive_balance);
        } else {
            let balance_bm = df::borrow_mut<vector<u8>, Balance<T>>(&mut tick_record.id, INCENTIVE_FIELD_NAME);
            balance::join<T>(balance_bm, incentive_balance);
        };
    }

    public(friend) fun borrow_mut_incentive<T: drop>(tick_record: &mut TickRecordV2) : &mut Balance<T> {
        df::borrow_mut(&mut tick_record.id, INCENTIVE_FIELD_NAME)
    }

    public(friend) fun borrow_incentive<T: drop>(tick_record: &TickRecordV2) : &Balance<T> {
        df::borrow(&tick_record.id, INCENTIVE_FIELD_NAME)
    }

    // ===== Dynamic Field functions =====

    /// Add the `Value` type dynamic field to the movescription
    fun add_df<Value: store>(
        movescription: &mut Movescription,
        value: Value,
    ) {
        let name = type_to_name<Value>();
        df::add(&mut movescription.id, name, value);
    }

    /// Borrow the `Value` type dynamic field of the movescription
    fun borrow_df<Value: store>(
        movescription: &Movescription,
    ): &Value {
        let name = type_to_name<Value>();
        df::borrow<String, Value>(&movescription.id, name)
    }

    /// Borrow the `Value` type dynamic field of the movescription mutably
    fun borrow_df_mut<Value: store>(
        movescription: &mut Movescription,
    ): &mut Value {
        let name = type_to_name<Value>();
        df::borrow_mut<String, Value>(&mut movescription.id, name)
    }

    /// Returns the `Value` type dynamic field of the movescription
    fun remove_df<Value: store>(
        movescription: &mut Movescription,
    ): Value {
        let name = type_to_name<Value>();
        let value: Value = df::remove<String, Value>(&mut movescription.id, name);
        value
    }

    /// Add the `Value` type dynamic field to the movescription, it will add attach_coin count.
    /// If use this function add dynamic field, please use `remove_df_with_attach` to remove.
    fun add_df_with_attach<Value: store>(
        movescription: &mut Movescription,
        value: Value,
    ) {
        let name = type_to_name<Value>();
        movescription.attach_coin = movescription.attach_coin + 1;
        df::add(&mut movescription.id, name, value);
    }

    /// Returns the `Value` type dynamic field of the movescription, it will reduce attach_coin count.
    /// If use this function remove dynamic field, please use `add_df_with_attach` to add before.
    fun remove_df_with_attach<Value: store>(
        movescription: &mut Movescription,
    ): Value {
        let name = type_to_name<Value>();
        // assert attach_coin > 0
        movescription.attach_coin = movescription.attach_coin - 1;
        let value: Value = df::remove<String, Value>(&mut movescription.id, name);
        value
    }

    /// Returns if the movescription contains the `Value` type dynamic field
    fun exists_df<Value: store>(
        movescription: &Movescription,
    ): bool {
        let name = type_to_name<Value>();
        df::exists_with_type<String, Value>(&movescription.id, name)
    }

    // ===== Locked Box functions =====

    /// Lock the locked_movescription in the movescription, and the locked_movescription can be unlocked when the movescription is burned
    public fun lock_within(movescription: &mut Movescription, locked_movescription: Movescription) {
        if (exists_df<LockedBox>(movescription)) {
            let locked_box = borrow_df_mut<LockedBox>(movescription);
            do_merge(&mut locked_box.locked_movescription, locked_movescription);
        } else {
            let locked_box = LockedBox {
                locked_movescription
            };
            add_df(movescription, locked_box);
        }
    }

    public fun contains_locked(movescription: &Movescription): bool {
        exists_df<LockedBox>(movescription)
    }

    public fun borrow_locked(movescription: &Movescription): &Movescription {
        let locked_box = borrow_df<LockedBox>(movescription);
        &locked_box.locked_movescription
    }

    fun borrow_mut_locked(movescription: &mut Movescription): &mut Movescription {
        let locked_box = borrow_df_mut<LockedBox>(movescription);
        &mut locked_box.locked_movescription
    }

    fun unlock_box(movescription: &mut Movescription) : Movescription {
        let LockedBox{ locked_movescription } = remove_df<LockedBox>(movescription);
        locked_movescription
    }

    // ===== check tick util functions ===== 

    // Security by check tick
    public fun check_tick(ms: &Movescription, tick: vector<u8>): bool {
        to_uppercase(&mut tick);
        ascii::into_bytes(ms.tick) == tick
    }

    public fun check_tick_record(tick_record: &TickRecordV2, tick: vector<u8>): bool {
        to_uppercase(&mut tick);
        ascii::into_bytes(tick_record.tick) == tick
    }

    // ======== DeployRecord Read Functions =========

    public fun is_deployed(deploy_record: &DeployRecord, tick: vector<u8>): bool {
        to_uppercase(&mut tick);
        let tick_str: String = string(tick);
        table::contains(&deploy_record.record, tick_str)
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

    public fun tick_record_v2_burned_amount(tick_record: &TickRecordV2): u64 {
        tick_record.total_supply - tick_record.stat.current_supply - tick_record.stat.remain
    }

    // ======== TickRecordV2 df functions =========

    public fun tick_record_add_df<V: store, W: drop>(tick_record: &mut TickRecordV2, value: V, _witness: W) {
        type_util::assert_witness<W>(tick_record.mint_factory);
        tick_record_add_df_internal(tick_record, value);
    }

    public(friend) fun tick_record_add_df_internal<V: store>(tick_record: &mut TickRecordV2, value: V) {
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
        tick_record_borrow_mut_df_internal(tick_record)
    }

    public(friend) fun tick_record_borrow_mut_df_internal<V: store>(tick_record: &mut TickRecordV2) : &mut V {
        let name = type_util::type_to_name<V>();
        df::borrow_mut(&mut tick_record.id, name)
    }

    public fun tick_record_borrow_df<V: store>(tick_record: &TickRecordV2) : &V{
        let name = type_util::type_to_name<V>();
        df::borrow(&tick_record.id, name) 
    }

    public fun tick_record_exists_df<V: store>(tick_record: &TickRecordV2) : bool {
        let name = type_util::type_to_name<V>();
        df::exists_with_type<String, V>(&tick_record.id, name) 
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

    public fun unpack_metadata(metadata: Metadata): (std::string::String, vector<u8>){
        let Metadata{content_type, content} = metadata;
        (content_type, content)
    }

    // ======= Internal cap functions ========

    public(friend) fun is_movescription_publisher(publisher: &Publisher): bool{
        package::from_module<Movescription>(publisher)
    }

    // ======== Constants functions =========
    
    /// Deprecated, use `tick_name::move_tick` instead
    public fun protocol_tick(): vector<u8> {
        tick_name::move_tick()
    }

    public fun protocol_start_time_ms(): u64 {
        PROTOCOL_START_TIME_MS
    }

    /// Deprecated, use `move_tick_total_supply` instead
    public fun protocol_tick_total_supply(): u64{
        MOVE_TICK_TOTAL_SUPPLY
    }

    public fun move_tick_total_supply(): u64{
        MOVE_TICK_TOTAL_SUPPLY
    } 

    public fun mcoin_decimals(): u8{
        MCOIN_DECIMALS
    }

    public fun mcoin_decimals_base(): u64{
        MCOIN_DECIMALS_BASE
    }

    // ===== Migrate functions =====

    public fun migrate_deploy_record(deploy_record: &mut DeployRecord) {
        assert!(deploy_record.version <= VERSION, ErrorVersionMismatched);
        deploy_record.version = VERSION;
    }

    public fun migrate_tick_record(tick_record: &mut TickRecord) {
        assert!(tick_record.version <= VERSION, ErrorVersionMismatched);
        tick_record.version = VERSION;
    }

    public(friend) fun migrate_tick_record_to_v2<W: drop>(
        deploy_record: &mut DeployRecord, 
        tick_record: TickRecord, 
        _witness: W, 
        ctx: &mut TxContext) : 
        (TickRecordV2, u64, u64, u64, u64, Table<u64, EpochRecord>) {
        assert!(deploy_record.version <= VERSION, ErrorVersionMismatched);
        let TickRecord { id, version: _, tick, total_supply, start_time_ms, epoch_count, current_epoch, remain, mint_fee, epoch_records, current_supply, total_transactions } = tick_record;
        
        let mint_factory = type_util::module_id<W>();
        let tick_record_v2: TickRecordV2 = TickRecordV2 {
            id: object::new(ctx),
            version: VERSION,
            tick: tick,
            total_supply,
            burnable: true,
            mint_factory,
            stat: TickStat {
                remain,
                current_supply,
                total_transactions,
            },
        };
        //remove the old tick record
        table::remove(&mut deploy_record.record, tick);
        let tick_record_v2_address: address = object::id_address(&tick_record_v2);
        table::add(&mut deploy_record.record, tick, tick_record_v2_address);
        object::delete(id);
        (tick_record_v2, start_time_ms, epoch_count, current_epoch, mint_fee, epoch_records)
    }

    public(friend) fun migrate_tick_record_to_v2_no_drop<W: drop>(
        deploy_record: &mut DeployRecord, 
        tick_record: &mut TickRecord, 
        _witness: W, 
        ctx: &mut TxContext) : 
        (TickRecordV2, u64, u64, u64, u64) {
        assert!(deploy_record.version <= VERSION, ErrorVersionMismatched);
        assert!(tick_record.version < VERSION, ErrorVersionMismatched);
        tick_record.version = VERSION;

        let mint_factory = type_util::module_id<W>();
        let tick_record_v2: TickRecordV2 = TickRecordV2 {
            id: object::new(ctx),
            version: VERSION,
            tick: tick_record.tick,
            total_supply: tick_record.total_supply,
            burnable: true,
            mint_factory,
            stat: TickStat {
                remain: tick_record.remain,
                current_supply: tick_record.current_supply,
                total_transactions: tick_record.total_transactions,
            },
        };
        //remove the old tick record
        table::remove(&mut deploy_record.record, tick_record.tick);
        let tick_record_v2_address: address = object::id_address(&tick_record_v2);
        table::add(&mut deploy_record.record, tick_record.tick, tick_record_v2_address);
        
        (tick_record_v2, tick_record.start_time_ms, tick_record.epoch_count, tick_record.current_epoch, tick_record.mint_fee)
    }

    public(friend) fun tick_record_epoch_records(tick_record: &mut TickRecord) : &mut Table<u64, EpochRecord> {
        &mut tick_record.epoch_records
    }

    /// This function use acc to stake validator
    public entry fun stake_movescription_acc(
        wrapper: &mut SuiSystemState,
        validator_address: address,
        movescription: &mut Movescription,
        ctx: &mut TxContext
    ){
        let value = acc(movescription);
        let stake = withdraw_acc(movescription, value, ctx);
        let staked_sui = request_add_stake_non_entry(wrapper, stake, validator_address, ctx);
        // assert not staked before
        add_df_with_attach(movescription, staked_sui)
    }

    /// This function unstake validator and return coin to acc.
    public entry fun withdraw_stake_movescription_acc(
        wrapper: &mut SuiSystemState,
        movescription: &mut Movescription,
        ctx: &mut TxContext,
    ){
        // assert staked before
        let staked_sui = remove_df_with_attach<StakedSui>(movescription);
        movescription.attach_coin = movescription.attach_coin - 1;
        let sui = request_withdraw_stake_non_entry(wrapper, staked_sui, ctx);
        balance::join(&mut movescription.acc, sui);
    }

    fun withdraw_acc(movescription: &mut Movescription, value: u64, ctx: &mut TxContext): Coin<SUI> {
        assert!(value <= acc(movescription), ErrorNotEnoughBalance);
        coin::take(&mut movescription.acc, value, ctx)
    }

    // ========= Test Functions =========

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(MOVESCRIPTION{}, ctx);
    }

    #[test_only]
    public fun deploy_for_testing<W: drop>(
        deploy_record: &mut DeployRecord,
        tick: String,
        total_supply: u64,
        burnable: bool,
        witness: W,
        ctx: &mut TxContext
    ) : TickRecordV2 {
        internal_deploy_with_witness(deploy_record, tick, total_supply, burnable, witness, ctx)
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

    #[test_only]
    public fun new_tick_record_for_testing<W: drop>(
        tick: String,
        total_supply: u64,
        current_supply: u64, 
        burnable: bool,
        _witness: W,
        ctx: &mut TxContext
    ) : TickRecordV2 {
        let tick_uid = object::new(ctx);
        let mint_factory = type_util::module_id<W>();
        let tick_record: TickRecordV2 = TickRecordV2 {
            id: tick_uid,
            version: VERSION,
            tick: tick,
            total_supply,
            burnable,
            mint_factory,
            stat: TickStat {
                remain: total_supply - current_supply,
                current_supply,
                total_transactions: 0,
            },
        };
        tick_record
    }

    #[test_only]
    public fun drop_tick_record_for_testing(tick_record: TickRecordV2) {
        let TickRecordV2 { id, version: _, tick: _, total_supply: _, burnable: _,  mint_factory: _, stat: _ } = tick_record;
        object::delete(id);
    }

    #[test_only]
    public fun init_treasury_for_testing<T: drop>(tick_record: &mut TickRecordV2, ctx: &mut TxContext) {
        let cap = coin::create_treasury_cap_for_testing<T>(ctx);
        let args = InitTreasuryArgs<T> {
            id: object::new(ctx),
            tick: tick_record.tick,
            cap: option::some(cap),
        };
        init_treasury(tick_record, &mut args);
        let InitTreasuryArgs { id, tick: _, cap} = args;
        option::destroy_none(cap);
        object::delete(id);
    }

    #[test_only]
    public fun movescription_to_coin_for_testing<T: drop>(
        tick_record: &mut TickRecordV2, 
        movescription: Movescription):(Balance<SUI>, Option<Movescription>, Option<Metadata>, Balance<T>){
        movescription_to_coin(tick_record, movescription)
    }

    #[test_only]
    public fun coin_to_movescription_for_testing<T: drop>(
        tick_record: &mut TickRecordV2, 
        acc: Balance<SUI>, 
        locked: Option<Movescription>, 
        metadata: Option<Metadata>, 
        balance_t: Balance<T>, 
        ctx: &mut TxContext
    ): (Movescription, Balance<T>) {
        coin_to_movescription(tick_record, acc, locked, metadata, balance_t, ctx)
    }

    #[test_only]
    public fun borrow_incentive_for_testing<T: drop>(tick_record: &TickRecordV2): &Balance<T> {
        borrow_incentive<T>(tick_record)
    }

    #[test_only]
    public fun borrow_mut_incentive_for_testing<T: drop>(tick_record: &mut TickRecordV2): &mut Balance<T> {
        borrow_mut_incentive<T>(tick_record)
    }

    // ====== Deprecated Structs and  Functions ======

    struct InscriptionBalance<phantom T> has copy, drop, store { }

     #[allow(unused_field)]
    struct EpochRecord has store {
        epoch: u64,
        start_time_ms: u64,
        players: vector<address>,
        mint_fees: Table<address, Balance<SUI>>,
    }

    public(friend) fun unwrap_epoch_record(epoch_record: EpochRecord): (u64, u64, vector<address>, Table<address, Balance<SUI>>) {
        let EpochRecord { epoch, start_time_ms, players, mint_fees } = epoch_record;
        (epoch, start_time_ms, players, mint_fees)
    }

    // clean the epoch record after the tick mint is finished
    public fun clean_finished_tick_record(tick_record: &mut TickRecord, batch_size: u64) {
        assert!(tick_record.remain == 0, 1000);
        let epoch_records_length = table::length(&tick_record.epoch_records);
        let batch_size = sui::math::min(batch_size, epoch_records_length);
        let epoch = epoch_records_length - 1;
        let delete_count = 0;
        while(epoch > 0 && delete_count < batch_size){
            if(table::contains(&tick_record.epoch_records, epoch)){
                let epoch_record = table::remove(&mut tick_record.epoch_records, epoch);
                let (_, _, _, mint_fees) = unwrap_epoch_record(epoch_record);
                table::destroy_empty(mint_fees);
                delete_count = delete_count + 1;
            };
            epoch = epoch - 1;
        };
    }

    public fun clean_finished_tick_record_via_epoch(tick_record: &mut TickRecord, epoch: u64) {
        assert!(tick_record.remain == 0, 1000);
        if(table::contains(&tick_record.epoch_records, epoch)){
            let epoch_record = table::remove(&mut tick_record.epoch_records, epoch);
            let (_, _, _, mint_fees) = unwrap_epoch_record(epoch_record);
            table::destroy_empty(mint_fees);
        };
    }

    public fun clean_old_invalid_not_start_tick_record(deploy_record: &mut DeployRecord, tick_record: &mut TickRecord) {
        tick_record.version = VERSION;

        let tick = tick_record.tick;
        if (!tick_name::is_tick_name_valid(ascii::into_bytes(tick)) && tick_record.current_epoch ==0 && tick_record.total_transactions == 0){
            table::remove(&mut deploy_record.record, tick);
        };
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

    #[allow(unused_field)]
    struct MintTick has copy, drop {
        sender: address,
        tick: String,
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
        abort ErrorDeprecatedFunction
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
        abort ErrorDeprecatedFunction
    }

    public fun do_mint(
        _tick_record: &mut TickRecord,
        _fee_coin: Coin<SUI>,
        _clk: &Clock,
        _ctx: &mut TxContext
    ) {
        abort ErrorDeprecatedFunction
    }


    public entry fun mint(
        _tick_record: &mut TickRecord,
        _tick: vector<u8>,
        _fee_coin: Coin<SUI>,
        _clk: &Clock,
        _ctx: &mut TxContext
    ) {
        abort ErrorDeprecatedFunction
    }

    /// Burn inscription and return the acc SUI, without message and BurnRecipt
    public fun do_burn(
        _tick_record: &mut TickRecord,
        _inscription: Movescription,
        _ctx: &mut TxContext
    ) : Coin<SUI> {
        abort ErrorDeprecatedFunction
    }

    /// Burn Movescription without BurnRecipt
    public fun do_burn_with_message(
        _tick_record: &mut TickRecord,
        _inscription: Movescription,
        _message: vector<u8>,
        _ctx: &mut TxContext
    ) : Coin<SUI> {
        abort ErrorDeprecatedFunction
    }

    public fun do_burn_for_receipt(
        _tick_record: &mut TickRecord,
        _inscription: Movescription,        
        _message: vector<u8>,
        _ctx: &mut TxContext
    ) : (Coin<SUI>, BurnReceipt) {
        abort ErrorDeprecatedFunction
    }

    public entry fun burn(
        _tick_record: &mut TickRecord,
        _inscription: Movescription,
        _ctx: &mut TxContext
    ) {
        abort ErrorDeprecatedFunction
    }

    public entry fun burn_for_receipt(
        _tick_record: &mut TickRecord,
        _inscription: Movescription,        
        _message: vector<u8>,
        _ctx: &mut TxContext
    ) {
        abort ErrorDeprecatedFunction
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

    public fun calculate_deploy_fee(_tick: vector<u8>, _epoch_count: u64): u64 {
        abort ErrorDeprecatedFunction
    }

    /// Deprecated function, use `epoch_bus_factory::epoch_duration_ms` instead
    public fun epoch_duration_ms(): u64 {
        60 * 1000
    }

    /// Deprecated function, use `epoch_bus_factory::min_epochs` instead
    public fun min_epochs(): u64 {
        60*2
    }

    /// Deprecated function, use `epoch_bus_factory::max_epochs` instead
    public fun epoch_max_player(): u64 {
        500
    }

    /// Deprecated function, use `epoch_bus_factory::epoch_count_of_move` instead
    public fun base_epoch_count(): u64 {
        60*24*15
    }
}