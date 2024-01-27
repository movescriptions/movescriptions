module smartinscription::util {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use smartinscription::movescription::{Self, Movescription};

    #[lint_allow(self_transfer)]
    /// Split the movescription into two movescription, one with the given amount and the other with the remaining amount.
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
}