// Copyright 2019-2022 SwiftNFT Systems
// SPDX-License-Identifier: Apache-2.0
module smartinscription::market_event {
    use sui::object::ID;
    use sui::event;
    use std::ascii::String;

    struct MarketCreatedEvent has copy, drop {
        market_id: ID,
        owner: address,
    }

    struct ListedEvent has copy, drop {
        id: ID,
        operator: address,
        price: u64,
        inscription_amount: u64
    }

    struct BuyEvent has copy, drop {
        id: ID,
        from: address,
        to: address,
        price: u64,
        per_price: u64,
    }

    struct CollectionWithdrawalEvent has copy, drop {
        collection_id: ID,
        from: address,
        to: address,
        nft_type: String,
        ft_type: String,
        price: u64,
    }

    struct DeListedEvent has copy, drop {
        id: ID,
        operator: address,
        price: u64,

    }

    struct ModifyPriceEvent has copy, drop {
        id: ID,
        operator: address,
        price: u64,
    }

    public fun market_created_event(market_id: ID, owner: address) {
        event::emit(MarketCreatedEvent {
            market_id,
            owner
        })
    }

    public fun list_event(id: ID, operator: address, price: u64, inscription_amount: u64) {
        event::emit(ListedEvent {
            id,
            operator,
            price,
            inscription_amount
        })
    }

    public fun buy_event(id: ID, from: address, to: address, price: u64, per_price: u64) {
        event::emit(BuyEvent {
            id,
            from,
            to,
            price,
            per_price
        })
    }

    public fun collection_withdrawal(collection_id: ID, from: address, to: address, nft_type: String, ft_type: String, price: u64) {
        event::emit(CollectionWithdrawalEvent {
            collection_id,
            from,
            to,
            nft_type,
            ft_type,
            price
        })
    }

    public fun delisted_event( id: ID, operator: address, price: u64) {
        event::emit(DeListedEvent {
            id,
            operator,
            price,
        })
    }

    public fun modify_price_event(id: ID, operator: address, price: u64) {
        event::emit(ModifyPriceEvent {
            id,
            operator,
            price
        })
    }

}
