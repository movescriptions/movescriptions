#[test_only]
module smartinscription::name_factory_scenario_test{
    use std::option;
    use sui::clock;
    use sui::transfer;
    use sui::test_scenario;
    use sui::balance;
    use smartinscription::movescription::{Self, TickRecordV2};
    use smartinscription::name_factory;
    use smartinscription::scenario_test;
    use smartinscription::epoch_bus_factory;
    use smartinscription::metadata;

    #[test_only]
    struct WITNESS has drop{}

    #[test]
    #[lint_allow(self_transfer, share_owned)]
    public fun test_whole_process() {

        let sender = @0xABBA;
        let test_name = b"alice";
        let test_name2 = b"bob1";
        let test_name2_upper = b"BOB1";
     
        let scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;


        let (clk, deploy_record, tick_tick_record, move_tick_record) = scenario_test::init_for_testing(scenario);

        test_scenario::next_tx(scenario, sender);

        let name_tick_record = {
            name_factory::deploy_name_tick(&mut deploy_record, test_scenario::ctx(scenario));
            test_scenario::next_tx(scenario, sender);
            test_scenario::take_shared<TickRecordV2>(scenario)
        };
        
        test_scenario::next_tx(scenario, sender);
        {
            //Mint the NAME movescription, register the test_name
            let locked_move = epoch_bus_factory::mint_for_testing(&mut move_tick_record, name_factory::init_locked_move(), balance::zero(), test_scenario::ctx(scenario));
            let name_movescription = name_factory::do_mint(&mut name_tick_record, locked_move, test_name, &clk, test_scenario::ctx(scenario)); 
        
            assert!(movescription::amount(&name_movescription) == 1, 1);
            //std::debug::print(&name_movescription);
            assert!(std::ascii::into_bytes(movescription::tick(&name_movescription)) == name_factory::tick(), 2);
            let metadata_opt = movescription::metadata(&name_movescription);
            assert!(option::is_some(&metadata_opt), 3);
            let metadata = option::destroy_some(metadata_opt);

            let name_metadata = metadata::decode_text_metadata(&metadata);
            assert!(metadata::text_metadata_text(&name_metadata) == &test_name, 5);
            assert!(metadata::text_metadata_miner(&name_metadata) == sender, 6);
            transfer::public_transfer(name_movescription, sender);
        };
        
        test_scenario::next_tx(scenario, sender);
        //test burn name and recycle
        {
            //Mint a NAME movescription, register test_name2 
            let locked_move = epoch_bus_factory::mint_for_testing(&mut move_tick_record, name_factory::init_locked_move(), balance::zero(), test_scenario::ctx(scenario));
            let test_name2_movescription = name_factory::do_mint(&mut name_tick_record, locked_move, test_name2_upper, &clk, test_scenario::ctx(scenario)); 

            assert!(!name_factory::is_name_available(&name_tick_record, test_name2), 7);
            assert!(!name_factory::is_name_available(&name_tick_record, test_name2_upper), 7);

            let metadata = option::destroy_some(movescription::metadata(&test_name2_movescription));
            let name_metadata = metadata::decode_text_metadata(&metadata);
            assert!(metadata::text_metadata_text(&name_metadata) == &test_name2, 5);

            test_scenario::next_tx(scenario, sender);
            let before_total_name_fee = name_factory::total_name_fee(&name_tick_record);
            name_factory::burn(&mut name_tick_record, test_name2_movescription, &clk, test_scenario::ctx(scenario));
            let after_total_name_fee = name_factory::total_name_fee(&name_tick_record);
            assert!(after_total_name_fee > before_total_name_fee , 8);
            assert!(name_factory::is_name_available(&name_tick_record, test_name2), 9);
        };

        test_scenario::return_shared(name_tick_record);

        clock::destroy_for_testing(clk);
        test_scenario::return_shared(deploy_record);
        test_scenario::return_shared(tick_tick_record);
        test_scenario::return_shared(move_tick_record);
        test_scenario::end(scenario_val);
    }
    
}