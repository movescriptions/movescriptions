#[test_only]
module smartinscription::test_movescription {
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::transfer;
    use sui::object;
    use sui::test_scenario::{Self, Scenario};
    use smartinscription::movescription::{Self, Movescription};

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
        let start_time_ms = movescription::protocol_start_time_ms();
        let epoch_count = movescription::min_epochs();
        let total_supply = 21000000;
        let epoch_amount = total_supply / epoch_count;
        clock::increment_for_testing(&mut c, start_time_ms);

        test_scenario::next_tx(scenario, admin);
        let move_tick = {
            movescription::init_for_testing(test_scenario::ctx(scenario));
            //Need to start a new tx to get the shared object
            test_scenario::next_tx(scenario, admin);
            test_scenario::take_shared<movescription::TickRecord>(scenario)
        };

        let move_tick_scription = mint_move_tick(scenario, &mut move_tick, admin, &mut c);
        let start_move_tick_amount = movescription::amount(&move_tick_scription);

        test_scenario::next_tx(scenario, admin);
        {
            let deploy_record = test_scenario::take_shared<movescription::DeployRecord>(scenario);
            let now_ms = clock::timestamp_ms(&c);
            let tick = b"test";
            movescription::deploy_v2(&mut deploy_record, &mut move_tick,&mut move_tick_scription, tick, total_supply, now_ms, epoch_count, 1000, &c, test_scenario::ctx(scenario));
            test_scenario::return_shared(deploy_record);
            let after_deploy_move_tick_amount = movescription::amount(&move_tick_scription);
            assert!(start_move_tick_amount - after_deploy_move_tick_amount == movescription::calculate_deploy_fee(tick, epoch_count), 0);
        };

        test_scenario::next_tx(scenario, admin);
        {
            let test_tick_record = test_scenario::take_shared<movescription::TickRecord>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(1001, test_scenario::ctx(scenario));
            movescription::mint(&mut test_tick_record, b"test", test_sui, &c, test_scenario::ctx(scenario));
            test_scenario::return_shared(test_tick_record); 
        };

        settle_epoch(scenario, admin, &mut c);
        
        test_scenario::next_tx(scenario, admin);
        {
            let test_tick_record = test_scenario::take_shared<movescription::TickRecord>(scenario);
            let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
            assert!(movescription::amount(&first_inscription) == epoch_amount, 1);

            let second_inscription = movescription::do_split(&mut first_inscription, 100, test_scenario::ctx(scenario));
            assert!(movescription::amount(&second_inscription) == 100, 1);
            movescription::merge(&mut first_inscription, second_inscription);
            //std::debug::print(&epoch_amount);
            //std::debug::print(&first_inscription);
            assert!(movescription::amount(&first_inscription) == epoch_amount, 1);
            transfer::public_transfer(first_inscription, admin);
            test_scenario::return_shared(test_tick_record);
        };

        // test mint by transfer
        test_scenario::next_tx(scenario, usera);
        {
            let test_tick_record = test_scenario::take_shared<movescription::TickRecord>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            transfer::public_transfer(test_sui, object::id_to_address(&object::id(&test_tick_record)));
            test_scenario::return_shared(test_tick_record);
        };

        settle_epoch(scenario, admin, &mut c);

        // The mint by transfer not work, need to figure out why
        // test_scenario::next_tx(scenario, usera);
        // {
        //     let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
        //     assert!(movescription::amount(&first_inscription) >0, 1);
        //     transfer::public_transfer(first_inscription, usera);
        // };

        while(true){
            test_scenario::next_tx(scenario, admin);
            {
                let test_tick_record = test_scenario::take_shared<movescription::TickRecord>(scenario);
                if (movescription::tick_record_remain(&test_tick_record) == 0) {
                    assert!(movescription::tick_record_current_supply(&test_tick_record) == total_supply, 1);
                    assert!(movescription::tick_record_current_epoch(&test_tick_record) == movescription::tick_record_epoch_count(&test_tick_record)-1, 2);
                    test_scenario::return_shared(test_tick_record);
                    break
                };
                let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
                movescription::mint(&mut test_tick_record, b"test", test_sui, &c, test_scenario::ctx(scenario));
                test_scenario::return_shared(test_tick_record); 
            };

            settle_epoch(scenario, admin, &mut c); 
        };

        //test burn

        test_scenario::next_tx(scenario, admin);
        {
            let test_tick_record = test_scenario::take_shared<movescription::TickRecord>(scenario);
            let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
            let amount = movescription::amount(&first_inscription);
            movescription::burn(&mut test_tick_record, first_inscription, test_scenario::ctx(scenario));
            assert!(movescription::tick_record_current_supply(&test_tick_record) == total_supply - amount, 1);
            test_scenario::return_shared(test_tick_record); 
        };

        transfer::public_transfer(move_tick_scription, admin);
        test_scenario::return_shared(move_tick);
        clock::destroy_for_testing(c);
        test_scenario::end(scenario_val);
    }

    fun mint_move_tick(scenario: &mut Scenario, move_tick: &mut movescription::TickRecord, sender: address, c: &mut clock::Clock) : Movescription{
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(100000000, test_scenario::ctx(scenario));
            movescription::mint(move_tick, b"MOVE", test_sui, c, test_scenario::ctx(scenario));
        };
        clock::increment_for_testing(c, movescription::epoch_duration_ms() + 1);

        // send a new tx to settle the previous epoch
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(100000000, test_scenario::ctx(scenario));
            movescription::mint(move_tick, b"MOVE", test_sui, c, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, sender);
        let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
        assert!(movescription::tick(&first_inscription) == std::ascii::string(b"MOVE"), 1);
        first_inscription
    }

    fun settle_epoch(scenario: &mut Scenario, sender: address, c: &mut clock::Clock) {
        clock::increment_for_testing(c, movescription::epoch_duration_ms() + 1);

        // send a new tx to settle the previous epoch
        test_scenario::next_tx(scenario, sender);
        {
            let test_tick_record = test_scenario::take_shared<movescription::TickRecord>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            movescription::mint(&mut test_tick_record, b"test", test_sui, c, test_scenario::ctx(scenario));
            test_scenario::return_shared(test_tick_record);
        };
    }
}