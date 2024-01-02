// Copyright 2019-2022 SwiftNFT Systems
// SPDX-License-Identifier: Apache-2.0
module smartinscription::market {
    use std::ascii::{String, string};
    use sui::object::{Self, ID, UID};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::dynamic_object_field as dof;
    use sui::pay;
    use sui::package;
    use std::vector;
    use sui::balance;
    use sui::balance::Balance;
    use smartinscription::movescription::{Movescription, tick, amount};
    // use sui::clock::{Clock};
    use smartinscription::critbit::{CritbitTree, find_leaf};
    use smartinscription::critbit;
    use smartinscription::market_event;
    use sui::table;
    use sui::table::Table;
    use sui::table_vec;
    use sui::table_vec::TableVec;
    use sui::transfer::public_transfer;

    // One-Time-Witness for the module.
    struct MARKET has drop {}

    const VERSION: u64 = 1;

    const EWrongVersion: u64 = 0;
    const EDoesNotExist: u64 = 1;
    const ENotAuthOperator: u64 = 2;
    const EInputCoin: u64 = 3;
    const ETickLength: u64 = 4;
    const EWrongMarket: u64 = 5;

    /// listing info in the market
    struct Listing has key, store {
        id: UID,
        /// The price of inscription
        price: u64,
        /// The seller of inscription
        seller: address,
        /// The ID of the inscription
        inscription_id: ID,
        /// The price per inscription
        inscription_price: u64,
        /// the amp per inscription
        amt: u64
    }

    ///Record some important information of the market
    struct Marketplace has key {
        id: UID,
        /// the tick of market
        tick: String,
        /// version of market
        version: u64,
        /// marketplace fee collected by marketplace
        balance: Balance<SUI>,
        /// marketplace fee  of the marketplace
        fee: u64,
        /// listing cribit tree
        listing: CritbitTree<vector<Listing>>,
    }

    // struct TradeInfo has key, store {
    //     id: UID,
    //     tick: String,
    //     timestamp: u64,
    //     yesterday_balance: u64,
    //     today_balance: u64,
    //     total_balance: u64,
    // }

    struct AdminCap has key, store {
        id: UID,
    }

    struct MarketplaceHouse has key {
        id: UID,
        market_info: Table<String, ID>,
        markets: TableVec<String>,
    }


    public entry fun createMarket(
        tick: vector<u8>,
        market_house: &mut MarketplaceHouse,
        // clock: &Clock,
        ctx: &mut TxContext){
        assert!(vector::length(&tick) == 4, ETickLength);
        let market = Marketplace {
            id: object::new(ctx),
            tick: string(tick),
            version: VERSION,
            balance: balance::zero<SUI>(),
            fee: 0,
            listing: critbit::new(ctx)
        };
        // let trade_info = TradeInfo{
        //     id: object::new(ctx),
        //     tick: utf8(tick),
        //     timestamp: timestamp_ms(clock),
        //     yesterday_balance: 0,
        //     today_balance: 0,
        //     total_balance: 0
        // };
        table::add(&mut market_house.market_info, string(tick), object::id(&market));
        table_vec::push_back(&mut market_house.markets, string(tick));
        market_event::market_created_event(object::id(&market), tx_context::sender(ctx));
        // dynamic_field::add(&mut market.id, 0u8, trade_info);
        transfer::share_object(market);
    }

    fun init(otw: MARKET, ctx: &mut TxContext) {
        //Initialize the marketplace object and set the marketpalce fee
        let market = Marketplace {
            id: object::new(ctx),
            tick: string(b"MOVE"),
            version: VERSION,
            balance: balance::zero<SUI>(),
            fee: 0,
            listing: critbit::new(ctx)
        };
        let market_info = table::new<String, ID>(ctx);
        // let trade_info = TradeInfo{
        //     id: object::new(ctx),
        //     tick: utf8(b"MOVE"),
        //     timestamp: 0,
        //     yesterday_balance: 0,
        //     today_balance: 0,
        //     total_balance: 0
        // };
        table::add(&mut market_info, string(b"MOVE"), object::id(&market));

        let market_house = MarketplaceHouse {
            id: object::new(ctx),
            market_info,
            markets: table_vec::singleton(string(b"MOVE"), ctx)
        };
        // Claim the `Publisher` for the package!
        let publisher = package::claim(otw, ctx);
        transfer::public_transfer(publisher, sender(ctx));
        market_event::market_created_event(object::id(&market), tx_context::sender(ctx));
        // dynamic_field::add(&mut market.id, 0u8, trade_info);
        transfer::share_object(market);
        transfer::share_object(market_house);
        transfer::public_transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
    }

    ///Listing NFT in the collection
    public entry fun list(
        market: &mut Marketplace,
        inscription: Movescription,
        price: u64,
        ctx: &mut TxContext
    ) {
        assert!(market.tick == tick(&inscription), EWrongMarket);
        let inscription_id = object::id(&inscription);
        let inscription_amount = amount(&inscription);
        let inscription_price = price / inscription_amount;
        let listing = Listing {
            id: object::new(ctx),
            price,
            seller: sender(ctx),
            inscription_id,
            inscription_price,
            amt: inscription_amount
        };
        let (find_price, index)= critbit::find_leaf(&market.listing, inscription_price);
        if(find_price)  {
            vector::push_back(critbit::borrow_mut_leaf_by_index(&mut market.listing, index), listing);
        }else {
            critbit::insert_leaf(&mut market.listing, inscription_price, vector::singleton(listing));
        };
        dof::add(&mut market.id, inscription_id, inscription);
        market_event::list_event(inscription_id, tx_context::sender(ctx), inscription_price, inscription_amount);
    }


    ///Adjusting the price of NFT
    public entry fun modify_price(
        market: &mut Marketplace,
        inscription_id: ID,
        last_price: u64,
        price: u64,
        ctx: &TxContext
    ) {
        let listing = borrow_mut_listing(&mut market.listing, last_price, inscription_id);
        assert!(listing.seller == sender(ctx), ENotAuthOperator);
        listing.price = price;
        market_event::modify_price_event(inscription_id, sender(ctx), price);
    }

    ///Cancel the listing of inscription
    public entry fun delist(
        market: &mut Marketplace,
        inscription_id: ID,
        last_price: u64,
        ctx: &TxContext
    ) {
        //Get the list from the collection
        let Listing{
            id,
            price,
            seller,
            inscription_id,
            inscription_price: _,
            amt: _,
        } = remove_listing(&mut market.listing, last_price, inscription_id);
        object::delete(id);
        //Determine the owner's authority
        assert!(sender(ctx) == seller, ENotAuthOperator);

        let inscription = dof::remove<ID, Movescription>(&mut market.id, inscription_id);
        //emit event
        market_event::delisted_event(inscription_id, seller, price);

        public_transfer(inscription, seller)
    }


    ///purchase
    public fun buy(
        market: &mut Marketplace,
        inscription_id: ID,
        paid: &mut Coin<SUI>,
        last_price: u64,
        // clock: &Clock,
        ctx: &mut TxContext
    ): Movescription {
        // let trade_info = dynamic_field::borrow_mut<u8, TradeInfo>(&mut market.id, 0u8);
        // trade_info.total_balance = trade_info.total_balance + coin::value(paid);
        // if (timestamp_ms(clock) - trade_info.timestamp > 86400000) {
        //     trade_info.today_balance = coin::value(paid);
        //     trade_info.yesterday_balance = trade_info.today_balance;
        //     trade_info.timestamp = timestamp_ms(clock);
        // }else {
        //     trade_info.today_balance = trade_info.today_balance + coin::value(paid);
        // };
        assert!(market.version == VERSION, EWrongVersion);
        let Listing{
            id,
            price,
            seller,
            inscription_id,
            inscription_price,
            amt: _,
        } = remove_listing(&mut market.listing, last_price, inscription_id);
        object::delete(id);
        assert!(coin::value(paid) >= price, EInputCoin);

        let market_fee = price * market.fee / 10000;
        let surplus = price - market_fee;

        assert!(surplus > 0, EInputCoin);

        pay::split_and_transfer(paid, surplus, seller, ctx);
        let market_value = coin::split<SUI>(paid, market_fee, ctx);
        balance::join(&mut market.balance, coin::into_balance(market_value));


        let inscription = dof::remove<ID, Movescription>(&mut market.id, inscription_id);
        market_event::buy_event(inscription_id, seller, sender(ctx), price, inscription_price);
        return inscription
    }



    public entry fun withdraw_profits(
        _admin: &AdminCap,
        market: &mut Marketplace,
        receiver: address,
        ctx: &mut TxContext
    ) {
        assert!(market.version == VERSION, EWrongVersion);
        let balances = balance::value(&market.balance);
        let coins = balance::split(&mut market.balance, balances);
        transfer::public_transfer(coin::from_balance(coins, ctx), receiver);
    }


    public entry fun update_market_fee(
        _admin: &AdminCap,
        market: &mut Marketplace,
        fee: u64,
        _ctx: &mut TxContext
    ) {
        assert!(market.version == VERSION, EWrongVersion);
        market.fee = fee
    }

    public entry fun change_admin(
        admin: AdminCap,
        receiver: address,
    ){
        transfer::public_transfer(admin, receiver);
    }

    fun borrow_mut_listing(listings: &mut CritbitTree<vector<Listing>>, price: u64, inscription_id: ID): &mut Listing {
        let price_level = critbit::borrow_mut_leaf_by_key(listings, price);

        let index = 0;
        let listings_count = vector::length(price_level);
        while (listings_count > index) {
            let listing = vector::borrow(price_level, index);
            // on the same price level, we search for the specified NFT
            if (inscription_id == listing.inscription_id) {
                break
            };

            index = index + 1;
        };

        assert!(index < listings_count, EDoesNotExist);
        let listing = vector::borrow_mut(price_level, index);
        listing
    }

    fun remove_listing(listings: &mut CritbitTree<vector<Listing>>, price: u64, inscription_id: ID): Listing {
        let price_level = critbit::borrow_mut_leaf_by_key(listings, price);

        let index = 0;
        let listings_count = vector::length(price_level);
        while (listings_count > index) {
            let listing = vector::borrow(price_level, index);
            // on the same price level, we search for the specified NFT
            if (inscription_id == listing.inscription_id) {
                break
            };

            index = index + 1;
        };

        assert!(index < listings_count, EDoesNotExist);

        let listing = vector::remove(price_level, index);
        if (vector::length(price_level) == 0) {
            // to simplify impl, always delete empty price level
            let (find, leaf_index) = find_leaf(listings, price);
            if (find) {
                vector::destroy_empty(critbit::remove_leaf_by_index(listings, leaf_index));
            }
        };

        listing
    }

    public fun floor_listing(market: &Marketplace, from: u64, start: u64): vector<ID> {
        let res = vector<ID>[];
        let i = 0;
        if (from == 0) {
            (from, _) = critbit::min_leaf(&market.listing);
        };
        let count = start;
        while (i < start+50) {
            let listing = critbit::borrow_leaf_by_key(&market.listing, from);
            let listings_count = vector::length(listing);
            while (listings_count > count) {
                vector::borrow(listing, count);
                count = count + 1;
                i = i + 1;
            };
            count = 0;
            let (key, index) = critbit::next_leaf(&market.listing, from);
            if (index != 0x8000000000000000) {
                from = key;
            }else {
                return res
            }
        };
        return res
    }
}
