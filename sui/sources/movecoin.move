module smartinscription::movecoin{
    use smartinscription::movescription::{Self, TickRecordV2};
    use smartinscription::assert_util;
    use smartinscription::tick_name;

    friend smartinscription::init;

    struct MOVE has drop {}

    public(friend) fun init_movecoin(tick_record: &mut TickRecordV2) {
        assert_util::assert_tick_record(tick_record, tick_name::move_tick());
        movescription::init_treasury(tick_record, MOVE{});
    }
}