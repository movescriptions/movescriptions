#[test_only]
module smartinscription::test_smartscription {
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::tx_context;
    use sui::transfer;
    use smartinscription::inscription;

    #[test]
    #[lint_allow(self_transfer)]
    public fun test_whole_process() {
        use sui::test_scenario;

        let admin = @0xABBA;
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
            inscription::deploy(&mut deploy_record, b"test", total_supply, start_time_ms, epoch_count, 1000, b"", test_scenario::ctx(scenario));
            test_scenario::return_shared(deploy_record);
        };

        test_scenario::next_tx(scenario, admin);
        {
            let test_tick_record = test_scenario::take_shared<inscription::TickRecord>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            inscription::mint(&mut test_tick_record, b"test", &mut test_sui, &c, test_scenario::ctx(scenario));
            transfer::public_transfer(test_sui, tx_context::sender(test_scenario::ctx(scenario)));
            test_scenario::return_shared(test_tick_record); 
        };

        clock::increment_for_testing(&mut c, inscription::epoch_duration_ms() + 1);

        test_scenario::next_tx(scenario, admin);
        {
            let test_tick_record = test_scenario::take_shared<inscription::TickRecord>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            inscription::mint(&mut test_tick_record, b"test", &mut test_sui, &c, test_scenario::ctx(scenario));
            transfer::public_transfer(test_sui, tx_context::sender(test_scenario::ctx(scenario)));
            test_scenario::return_shared(test_tick_record);
        };

        test_scenario::next_tx(scenario, admin);
        {
            let first_inscription = test_scenario::take_from_sender<inscription::Inscription>(scenario);
            assert!(inscription::amount(&first_inscription) == epoch_amount, 1);

            let second_inscription = inscription::do_split(&mut first_inscription, 100, test_scenario::ctx(scenario));
            assert!(inscription::amount(&second_inscription) == 100, 1);
            inscription::merge(&mut first_inscription, second_inscription);
            //std::debug::print(&epoch_amount);
            //std::debug::print(&first_inscription);
            assert!(inscription::amount(&first_inscription) == epoch_amount, 1);
            inscription::burn(first_inscription, test_scenario::ctx(scenario));
        };

        clock::destroy_for_testing(c);
        test_scenario::end(scenario_val);
    }
}