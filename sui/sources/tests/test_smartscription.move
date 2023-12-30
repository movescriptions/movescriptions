#[test_only]
module smartinscription::test_smartscription {
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::transfer;
    use sui::object;
    use sui::test_scenario::{Self, Scenario};
    use smartinscription::inscription;

    #[test]
    #[lint_allow(self_transfer)]
    public fun test_whole_process() {

        let admin = @0xABBA;
        let usera = @0x1234;
        // let non_coin_holder = @0x5678;
        // let black_hole = @0x0000;

        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        let c = clock::create_for_testing(test_scenario::ctx(scenario));
        let start_time_ms = 6000;
        let epoch_count = inscription::min_epochs();
        let total_supply = 21000000;
        let epoch_amount = total_supply / epoch_count;
        clock::increment_for_testing(&mut c, 6000);

        test_scenario::next_tx(scenario, admin);
        {
            inscription::init_for_testing(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, admin);
        {
            let deploy_record = test_scenario::take_shared<inscription::DeployRecord>(scenario);
            inscription::deploy(&mut deploy_record, b"test", total_supply, start_time_ms, epoch_count, 1000, b"", &c, test_scenario::ctx(scenario));
            test_scenario::return_shared(deploy_record);
        };

        test_scenario::next_tx(scenario, admin);
        {
            let test_tick_record = test_scenario::take_shared<inscription::TickRecord>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            inscription::mint(&mut test_tick_record, b"test", test_sui, &c, test_scenario::ctx(scenario));
            test_scenario::return_shared(test_tick_record); 
        };

        settle_epoch(scenario, admin, &mut c);

        test_scenario::next_tx(scenario, admin);
        {
            let test_tick_record = test_scenario::take_shared<inscription::TickRecord>(scenario);
            let first_inscription = test_scenario::take_from_sender<inscription::Inscription>(scenario);
            assert!(inscription::amount(&first_inscription) == epoch_amount, 1);

            let second_inscription = inscription::do_split(&mut first_inscription, 100, test_scenario::ctx(scenario));
            assert!(inscription::amount(&second_inscription) == 100, 1);
            inscription::merge(&mut first_inscription, second_inscription);
            //std::debug::print(&epoch_amount);
            //std::debug::print(&first_inscription);
            assert!(inscription::amount(&first_inscription) == epoch_amount, 1);
            transfer::public_transfer(first_inscription, admin);
            test_scenario::return_shared(test_tick_record);
        };

        // test mint by transfer
        test_scenario::next_tx(scenario, usera);
        {
            let test_tick_record = test_scenario::take_shared<inscription::TickRecord>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            transfer::public_transfer(test_sui, object::id_to_address(&object::id(&test_tick_record)));
            test_scenario::return_shared(test_tick_record);
        };

        settle_epoch(scenario, admin, &mut c);

        // The mint by transfer not work, need to figure out why
        // test_scenario::next_tx(scenario, usera);
        // {
        //     let first_inscription = test_scenario::take_from_sender<inscription::Inscription>(scenario);
        //     assert!(inscription::amount(&first_inscription) >0, 1);
        //     transfer::public_transfer(first_inscription, usera);
        // };

        while(true){
            test_scenario::next_tx(scenario, admin);
            {
                let test_tick_record = test_scenario::take_shared<inscription::TickRecord>(scenario);
                if (inscription::tick_record_remain(&test_tick_record) == 0) {
                    assert!(inscription::tick_record_current_supply(&test_tick_record) == total_supply, 1);
                    test_scenario::return_shared(test_tick_record);
                    break
                };
                let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
                inscription::mint(&mut test_tick_record, b"test", test_sui, &c, test_scenario::ctx(scenario));
                test_scenario::return_shared(test_tick_record); 
            };

            settle_epoch(scenario, admin, &mut c); 
        };

        //test burn

        test_scenario::next_tx(scenario, admin);
        {
            let test_tick_record = test_scenario::take_shared<inscription::TickRecord>(scenario);
            let first_inscription = test_scenario::take_from_sender<inscription::Inscription>(scenario);
            let amount = inscription::amount(&first_inscription);
            inscription::burn(&mut test_tick_record, first_inscription, test_scenario::ctx(scenario));
            assert!(inscription::tick_record_current_supply(&test_tick_record) == total_supply - amount, 1);
            test_scenario::return_shared(test_tick_record); 
        };

        clock::destroy_for_testing(c);
        test_scenario::end(scenario_val);
    }

    fun settle_epoch(scenario: &mut Scenario, sender: address, c: &mut clock::Clock) {
        clock::increment_for_testing(c, inscription::epoch_duration_ms() + 1);

        // send a new tx to settle the previous epoch
        test_scenario::next_tx(scenario, sender);
        {
            let test_tick_record = test_scenario::take_shared<inscription::TickRecord>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            inscription::mint(&mut test_tick_record, b"test", test_sui, c, test_scenario::ctx(scenario));
            test_scenario::return_shared(test_tick_record);
        };
    }
}