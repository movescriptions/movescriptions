#[test_only]
module smartinscription::tick_record_df_test_module1 {
    use sui::tx_context::{Self, TxContext};
    use smartinscription::movescription::{Self, TickRecordV2};

    struct WITNESS has drop{}

    struct DFValue has store, drop{
        value: u64,
    }

    public fun value(self: &DFValue) : u64{
        self.value
    }

    #[test_only]
    public fun new_tick_record(ctx: &mut TxContext): TickRecordV2{
        let tick_record = movescription::new_tick_record_for_testing(std::ascii::string(b"TEST_DF"), 10000, 100, true, WITNESS{}, ctx);
        movescription::tick_record_add_df(&mut tick_record, DFValue{value: 1}, WITNESS{});
        tick_record
    }

    #[test]
    fun test_remove_success(){
        let ctx = tx_context::dummy();
        let tick_record = new_tick_record(&mut ctx);
        assert!(movescription::tick_record_exists_df<DFValue>(&tick_record), 1);
        let _df_value = movescription::tick_record_remove_df<DFValue, WITNESS>(&mut tick_record, WITNESS{});
        movescription::drop_tick_record_for_testing(tick_record);
    }
}

#[test_only]
module smartinscription::tick_record_df_test_module2 {
    use sui::tx_context;
    use smartinscription::movescription;
    use smartinscription::tick_record_df_test_module1::{DFValue, new_tick_record, value};
    
    struct WITNESS has drop{}

    struct DFValue2 has store, drop{
        value: u64,
    }

    #[test]
    fun test_borrow_df(){
        let ctx = tx_context::dummy();
        let tick_record = new_tick_record(&mut ctx);
        let v = movescription::tick_record_borrow_df<DFValue>(&tick_record);
        assert!(value(v) == 1, 1);
        movescription::drop_tick_record_for_testing(tick_record);
    }

    #[test]
    #[expected_failure]
    fun test_borrow_mut_df_failure(){
        let ctx = tx_context::dummy();
        let tick_record = new_tick_record(&mut ctx);
        let v = movescription::tick_record_borrow_mut_df<DFValue, WITNESS>(&mut tick_record, WITNESS{});
        assert!(value(v) == 1, 2);
        movescription::drop_tick_record_for_testing(tick_record);
    }

    #[test]
    #[expected_failure]
    // can not remove other factory's tick record df
    fun test_remove_failure(){
        let ctx = tx_context::dummy();
        let tick_record = new_tick_record(&mut ctx);
        assert!(movescription::tick_record_exists_df<DFValue>(&tick_record), 1);
        let _df_value = movescription::tick_record_remove_df<DFValue, WITNESS>(&mut tick_record, WITNESS{});
        movescription::drop_tick_record_for_testing(tick_record);
    }

    #[test]
    #[expected_failure]
    // can not add df to other factory's tick record
    fun test_add_failure(){
        let ctx = tx_context::dummy();
        let tick_record = new_tick_record(&mut ctx);
        movescription::tick_record_add_df<DFValue2, WITNESS>(&mut tick_record, DFValue2{value: 2}, WITNESS{});
        movescription::drop_tick_record_for_testing(tick_record);
    }
}
