#[test_only]
module smartinscription::tick_factory_scenario_test {
    use std::option;
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::transfer;
    use sui::test_scenario;
    use smartinscription::movescription::{Self, Movescription};
    use smartinscription::tick_factory;
    use smartinscription::content_type;

    #[test]
    #[lint_allow(self_transfer)]
    public fun test_whole_process() {

        let admin = @0xABBA;
        let usera = @0x1234;
        let expected_tick_name = b"TEST";
     
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        let c = clock::create_for_testing(test_scenario::ctx(scenario));
        let start_time_ms = movescription::protocol_start_time_ms();
        
        clock::increment_for_testing(&mut c, start_time_ms);

        test_scenario::next_tx(scenario, admin);
        let move_tick = {
            movescription::init_for_testing(test_scenario::ctx(scenario));
            //Need to start a new tx to get the shared object
            test_scenario::next_tx(scenario, admin);
            test_scenario::take_shared<movescription::TickRecord>(scenario)
        };

        test_scenario::next_tx(scenario, admin);
        {
            let deploy_record = test_scenario::take_shared<movescription::DeployRecord>(scenario);
            tick_factory::deploy(&mut deploy_record, test_scenario::ctx(scenario));
            test_scenario::return_shared(deploy_record);
        };

        test_scenario::next_tx(scenario, usera);
        {
            let tick_name_tick_record = test_scenario::take_shared<movescription::TickRecordV2>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(tick_factory::init_locked_sui(), test_scenario::ctx(scenario));
            tick_factory::mint(&mut tick_name_tick_record, test_sui, expected_tick_name, &c, test_scenario::ctx(scenario)); 
            test_scenario::return_shared(tick_name_tick_record); 
        };
        
        test_scenario::next_tx(scenario, usera);
        {
            let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
            assert!(movescription::amount(&first_inscription) == 1, 1);
            //std::debug::print(&first_inscription);
            assert!(std::ascii::into_bytes(movescription::tick(&first_inscription)) == tick_factory::tick(), 2);
            let metadata_opt = movescription::metadata(&first_inscription);
            assert!(option::is_some(&metadata_opt), 3);
            let metadata = option::destroy_some(metadata_opt);
            assert!(content_type::is_text(&movescription::metadata_content_type(&metadata)), 4);
            assert!(movescription::metadata_content(&metadata) == expected_tick_name, 5);
            transfer::public_transfer(first_inscription, usera);
        };
       
        test_scenario::return_shared(move_tick);
        clock::destroy_for_testing(c);
        test_scenario::end(scenario_val);
    }
    
}