module dummy::dummy{
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use smartinscription::movescription::Movescription;
    
    struct Dummy has key {
        id: UID,
        movescription: Movescription,
    }

    public fun new(movescription: Movescription, tx_context: &mut TxContext) : Dummy {
        Dummy{
            id: object::new(tx_context),
            movescription: movescription,
        }
    }
}