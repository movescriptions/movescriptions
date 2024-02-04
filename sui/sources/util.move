module smartinscription::util {
    use std::option::{Self, Option};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use smartinscription::movescription::{Self, Movescription};

    #[lint_allow(self_transfer)]
    /// Split the movescription to two movescription, one with the given amount and the other with the remaining amount.
    /// The movescription with the given amount is returned and the movescription with the remaining amount is transferred to the sender.
    public fun split_and_give_back(ms: Movescription, amount: u64, ctx: &mut TxContext): Movescription {         
        if(movescription::amount(&ms) == amount){
            ms
        }else{
            let split_ms = movescription::do_split(&mut ms, amount, ctx);
            transfer::public_transfer(ms, tx_context::sender(ctx));
            split_ms
        }
    }

    /// Split the movescription to two movescription, one with the given amount and the other with the remaining amount.
    /// If no remaining, the second one will be option::none
    /// We do not decide to provide a `movescription::zero` function to create zero amount Movescription
    public fun split_and_return_remain(ms: Movescription, amount: u64, ctx: &mut TxContext): (Movescription, Option<Movescription>){
        if(movescription::amount(&ms) == amount){
            (ms, option::none())
        }else{
            let split_ms = movescription::do_split(&mut ms, amount, ctx);
            (split_ms, option::some(ms))
        }
    }

    #[lint_allow(self_transfer)]
    public fun split_coin_and_give_back<T>(coin: Coin<T>, amount: u64, ctx: &mut TxContext): Coin<T> {
        if(coin::value(&coin) == amount){
            coin
        }else{
            let split_coin = coin::split(&mut coin, amount, ctx);
            transfer::public_transfer(coin, tx_context::sender(ctx));
            split_coin
        }
    }
}