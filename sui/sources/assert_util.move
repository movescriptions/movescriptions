module smartinscription::assert_util{
    use std::ascii;
    use smartinscription::tick_name;
    use smartinscription::movescription::{Self, Movescription, TickRecordV2};

    const ErrorUnexpectedTick: u64 = 1;

    /// Assert the tick of Movescription is protocol tick `MOVE`
    public fun assert_move_tick(ms: &Movescription) {
        assert!(ascii::into_bytes(movescription::tick(ms)) == tick_name::move_tick(), ErrorUnexpectedTick);
    }

    /// Assert the tick of Movescription is protocol tick name tick `TICK`
    public fun assert_tick_tick(ms: &Movescription) {
        assert!(ascii::into_bytes(movescription::tick(ms)) == tick_name::tick_tick(), ErrorUnexpectedTick);
    }
    
    /// Assert the tick of Movescription is protocol tick name service tick `NAME`
    public fun assert_name_tick(ms: &Movescription) {
        assert!(ascii::into_bytes(movescription::tick(ms)) == tick_name::name_tick(), ErrorUnexpectedTick);
    }

    public fun assert_tick(ms: &Movescription, tick: vector<u8>) {
        assert!(movescription::check_tick(ms, tick), ErrorUnexpectedTick);
    }

    public fun assert_tick_record(tick_record: &TickRecordV2, tick: vector<u8>) {
        assert!(movescription::check_tick_record(tick_record, tick), ErrorUnexpectedTick);
    }
}