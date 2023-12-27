module smartinscription::inscription {
    use std::string::{Self, utf8, String};
    use std::option::Option;
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

    // ======== Constants =========
    const VERSION: u64 = 1;
    const FIVE_SECONDS_IN_MS: u64 = 5_000;
    const MAX_TICK_LENGTH: u64 = 32;
    const MIN_TICK_LENGTH: u64 = 4;
    const MAX_MINT_TIMES: u64 = 100_000_000;
    const MIN_MINT_TIMES: u64 = 10_000;
    const MAX_MINT_FEE: u64 = 10_000_000_000;

    // ======== Errors =========
    const ErrorTickLengthInvaid: u64 = 1;
    const ErrorTickAlreadyExists: u64 = 2;
    const ErrorTickNotExists: u64 = 3;
    const ENotEnoughSupply: u64 = 4;
    const EInappropriateMintTimes: u64 = 5;
    const EOverMaxPerMint: u64 = 6;
    const ENotEnoughToMint: u64 = 7;
    const EMintTooFrequently: u64 = 8;
    const EInvalidAmount: u64 = 9;
    const ENotSameTick: u64 = 10;
    const EBalanceDONE: u64 = 11;
    const ETooHighFee: u64 = 12;
    const ELockObject: u64 = 13;
    const EStillMinting: u64 = 14;

    // ======== Types =========
    struct Inscription has key, store {
        id: UID,
        amount: u64,
        tick: String,
        image_url: Option<String>,
        acc: Balance<SUI>,
        lock: bool,
    }

    struct InscriptionBalance<phantom T> has copy, drop, store { }

    struct DeployRecord has key {
        id: UID,
        record: Table<String, address>,
    }

    struct TickRecord has key {
        id: UID,
        tick: String,
        total_supply: u64,
        max_per_mint: u64,
        remain: u64,
        mint_fee: u64,
        image_url: Option<String>,
        mint_record: Table<address, u64>,
    }

    // ======== Events =========
    struct DeployTick has copy, drop {
        deployer: address,
        tick: String,
        total_supply: u64,
        max_per_mint: u64,
        mint_fee: u64,
    }

    struct MintTick has copy, drop {
        sender: address,
        tick: String,
        amount: u64,
    }

    // ======== Functions =========
    fun init(ctx: &mut TxContext) {
        let deploy_record = DeployRecord { id: object::new(ctx), record: table::new(ctx) };
        transfer::share_object(deploy_record);
    }

    public entry fun deploy(
        deploy_record: &mut DeployRecord, 
        tick: vector<u8>,
        total_supply: u64,
        max_per_mint: u64,
        mint_fee: u64,
        image_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let tick_str: String = utf8(tick);
        let tick_len: u64 = string::length(&tick_str);
        assert!(MIN_TICK_LENGTH <= tick_len && tick_len <= MAX_TICK_LENGTH, ErrorTickLengthInvaid);
        assert!(!table::contains(&deploy_record.record, tick_str), ErrorTickAlreadyExists);
        assert!(max_per_mint <= total_supply, ENotEnoughSupply);
        let mint_times: u64 = total_supply / max_per_mint;
        assert!(MIN_MINT_TIMES <= mint_times && mint_times <= MAX_MINT_TIMES, EInappropriateMintTimes);
        assert!(mint_fee <= MAX_MINT_FEE, ETooHighFee);
        let tick_record: TickRecord = TickRecord {
            id: object::new(ctx),
            tick: tick_str,
            total_supply,
            max_per_mint,
            remain: total_supply,
            mint_fee,
            image_url: string::try_utf8(image_url),
            mint_record: table::new(ctx)
        };
        let tk_record_address: address = object::id_address(&tick_record);
        table::add(&mut deploy_record.record, tick_str, tk_record_address);
        transfer::share_object(tick_record);
        emit(DeployTick {
            deployer: tx_context::sender(ctx),
            tick: tick_str,
            total_supply,
            max_per_mint,
            mint_fee,
        });
    }

    #[lint_allow(self_transfer)]
    public entry fun mint(
        tick_record: &mut TickRecord,
        tick: vector<u8>,
        amount: u64,
        mint_fee_coin: &mut Coin<SUI>,
        clk: &Clock,
        ctx: &mut TxContext
    ) {
        let sender: address = tx_context::sender(ctx);
        let tick_str: String = utf8(tick);
        assert!(tick_record.tick == tick_str, ErrorTickNotExists);  // parallel optimization
        let fee_coin: Coin<SUI> = coin::split(mint_fee_coin, tick_record.mint_fee, ctx);
        assert!(amount <= tick_record.max_per_mint, EOverMaxPerMint);
        assert!(tick_record.remain > 0, ENotEnoughToMint);
        let last_mint_time: u64 = 0;        
        if (!table::contains(&tick_record.mint_record, sender)) {
            table::add(&mut tick_record.mint_record, sender, clock::timestamp_ms(clk) - FIVE_SECONDS_IN_MS);
        } else {
            last_mint_time = *table::borrow(&tick_record.mint_record, sender);
        };
        assert!(clock::timestamp_ms(clk) - last_mint_time > FIVE_SECONDS_IN_MS, EMintTooFrequently);
        if (amount > tick_record.remain) {
            amount = tick_record.remain;
        };
        tick_record.remain = tick_record.remain - amount;

        let ins: Inscription = new_inscription(
            amount, tick_str, tick_record.image_url, fee_coin, ctx
        );

        transfer::public_transfer(ins, sender);
        emit(MintTick {
            sender: sender,
            tick: tick_str,
            amount,
        });
    }


    public entry fun merge(
        inscription1: &mut Inscription,
        inscription2: Inscription,
    ) {
        assert!(inscription1.tick == inscription2.tick, ENotSameTick);
        assert!(!inscription2.lock, ELockObject);

        let Inscription { id, amount, tick: _, image_url: _, acc, lock: _ } = inscription2;
        inscription1.amount = inscription1.amount + amount;
        balance::join<SUI>(&mut inscription1.acc, acc);
        object::delete(id);
    }

    #[lint_allow(self_transfer)]
    public entry fun burn(
        inscription: Inscription,
        ctx: &mut TxContext
    ) {
        assert!(!inscription.lock, ELockObject);
        let Inscription { id, amount: _, tick: _, image_url: _, acc, lock: _ } = inscription;
        let acc: Coin<SUI> = coin::from_balance<SUI>(acc, ctx);
        transfer::public_transfer(acc, tx_context::sender(ctx));
        object::delete(id);
    }

    public fun accept_coin<T>(inscription: &mut Inscription, sent: Receiving<Coin<T>>) {
        let coin = transfer::public_receive(&mut inscription.id, sent);
        let inscription_balance_type = InscriptionBalance<T>{};
        let inscription_uid = &mut inscription.id;

        if (df::exists_(inscription_uid, inscription_balance_type)) {
            let balance: &mut Coin<T> = df::borrow_mut(inscription_uid, inscription_balance_type);
            coin::join(balance, coin);
        } else {
            df::add(inscription_uid, inscription_balance_type, coin);
        }
    }

    public fun withdraw_all<T>(inscription: &mut Inscription): Coin<T> {
        let inscription_balance_type = InscriptionBalance<T>{};
        let inscription_uid = &mut inscription.id;
        assert!(df::exists_(inscription_uid, inscription_balance_type), EBalanceDONE);
        let return_coin: Coin<T> = df::remove(inscription_uid, inscription_balance_type);
        return_coin
    }

    public fun split(
        inscription: &mut Inscription,
        amount: u64,
        ctx: &mut TxContext
    ): Inscription {
        assert!(0 < amount && amount < inscription.amount, EInvalidAmount);
        inscription.amount = inscription.amount - amount;

        let ins: Inscription = new_inscription(
            amount, 
            inscription.tick,
            inscription.image_url,
            coin::zero<SUI>(ctx),
            ctx);
        ins
    }

    public fun free(inscription: &mut Inscription) {
        inscription.lock = false
    }

    public fun lock(inscription: &mut Inscription) {
        inscription.lock = true
    }

    public fun clean_mint_record(tick_record: &mut TickRecord, holder: address) {
        assert!(tick_record.remain == 0, EStillMinting);
        table::remove(&mut tick_record.mint_record, holder);
    } 

    fun new_inscription(
        amount: u64,
        tick: String,
        image_url: Option<String>,
        fee_coin: Coin<SUI>,
        ctx: &mut TxContext
    ): Inscription {
        let acc: Balance<SUI> = coin::into_balance<SUI>(fee_coin);
        Inscription {
            id: object::new(ctx),
            amount,
            tick,
            image_url,
            acc,
            lock: true,
        }
    }

    // ======== Read Functions =========
    public fun locked(inscription: &Inscription): bool {
        inscription.lock
    }

    public fun amount(inscription: &Inscription): u64 {
        inscription.amount
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}