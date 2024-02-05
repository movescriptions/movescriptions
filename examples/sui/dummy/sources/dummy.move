module dummy::dummy{
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use smartinscription::movescription::Movescription;
    use smartinscription::assert_util;
    
    struct Dummy has key {
        id: UID,
        movescription: Movescription,
    }

    public fun new(movescription: Movescription, tx_context: &mut TxContext) : Dummy {
        assert_util::assert_move_tick(&movescription);
        Dummy{
            id: object::new(tx_context),
            movescription: movescription,
        }
    }
}