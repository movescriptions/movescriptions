#[test_only]
module smartinscription::epoch_bus_factory_scenario_test {
    use std::ascii;
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::transfer;
    use sui::test_scenario::{Self, Scenario};
    use smartinscription::movescription::{Self, Movescription, TickRecordV2};
    use smartinscription::epoch_bus_factory;
    use smartinscription::tick_factory;

    #[test]
    #[lint_allow(self_transfer)]
    public fun test_whole_process() {

        let admin = @0xABBA;
        // let usera = @0x1234;
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
        let deploy_record = {
            movescription::init_for_testing(test_scenario::ctx(scenario));
            //Need to start a new tx to get the shared object
            test_scenario::next_tx(scenario, admin);
            test_scenario::take_shared<movescription::DeployRecord>(scenario)
        };

        test_scenario::next_tx(scenario, admin);
        let move_tick = {
            epoch_bus_factory::deploy_protocol_tick(&mut deploy_record, test_scenario::ctx(scenario));
            //Need to start a new tx to get the shared object
            test_scenario::next_tx(scenario, admin);
            test_scenario::take_shared<movescription::TickRecordV2>(scenario)
        };

        let move_tick_scription = mint_move_tick(scenario, &mut move_tick, admin, &mut c);

        test_scenario::next_tx(scenario, admin);
        let test_tick_record = {
            let now_ms = clock::timestamp_ms(&c);
            let tick_name = tick_factory::new_tick_movescription_for_testing(ascii::string(b"TEST"), now_ms, test_scenario::ctx(scenario));
            epoch_bus_factory::do_deploy(&mut deploy_record, tick_name, total_supply, 1000, now_ms, epoch_count, test_scenario::ctx(scenario));
            
            test_scenario::next_tx(scenario, admin);
            test_scenario::take_shared<movescription::TickRecordV2>(scenario)
        };

        test_scenario::next_tx(scenario, admin);
        {
            let test_sui = coin::mint_for_testing<SUI>(1001, test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(&mut test_tick_record, test_sui, &c, test_scenario::ctx(scenario));
        };

        settle_epoch(scenario, &mut test_tick_record, admin, &mut c);
        
        test_scenario::next_tx(scenario, admin);
        {
            let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
            assert!(movescription::amount(&first_inscription) == epoch_amount, 1);

            let second_inscription = movescription::do_split(&mut first_inscription, 100, test_scenario::ctx(scenario));
            assert!(movescription::amount(&second_inscription) == 100, 1);
            movescription::merge(&mut first_inscription, second_inscription);
            //std::debug::print(&epoch_amount);
            //std::debug::print(&first_inscription);
            assert!(movescription::amount(&first_inscription) == epoch_amount, 1);
            transfer::public_transfer(first_inscription, admin);
        };

        settle_epoch(scenario, &mut test_tick_record, admin, &mut c);

        while(true){
            test_scenario::next_tx(scenario, admin);
            {
                if (movescription::tick_record_v2_remain(&test_tick_record) == 0) {
                    assert!(movescription::tick_record_v2_current_supply(&test_tick_record) == total_supply, 1);
                    //assert!(movescription::tick_record_v2_current_epoch(&test_tick_record) == movescription::tick_record_v2_epoch_count(&test_tick_record)-1, 2);
                    break
                };
                let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
                epoch_bus_factory::do_mint(&mut test_tick_record,test_sui, &c, test_scenario::ctx(scenario));
            };

            settle_epoch(scenario, &mut test_tick_record, admin, &mut c); 
        };

        //test burn
        test_scenario::next_tx(scenario, admin);
        {
            let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
            let amount = movescription::amount(&first_inscription);
            let acc = movescription::acc(&first_inscription);
            let tick = movescription::tick(&first_inscription);
            let (coin, receipt) = movescription::do_burn_for_receipt_v2(&mut test_tick_record, first_inscription, b"love and peace", test_scenario::ctx(scenario));
            assert!(coin::value(&coin) == acc, 1);
            transfer::public_transfer(coin, admin);
            let (burn_tick, burn_amount) = movescription::drop_receipt(receipt);
            assert!(tick == burn_tick, 2);
            assert!(amount == burn_amount, 3);
            assert!(movescription::tick_record_v2_current_supply(&test_tick_record) == total_supply - amount, 4);
        };

        transfer::public_transfer(move_tick_scription, admin);
        test_scenario::return_shared(move_tick);
        test_scenario::return_shared(deploy_record);
        test_scenario::return_shared(test_tick_record);
        clock::destroy_for_testing(c);
        test_scenario::end(scenario_val);
    }

    fun mint_move_tick(scenario: &mut Scenario, move_tick: &mut movescription::TickRecordV2, sender: address, c: &mut clock::Clock) : Movescription{
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(100000000, test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(move_tick, test_sui, c, test_scenario::ctx(scenario));
        };
        clock::increment_for_testing(c, movescription::epoch_duration_ms() + 1);

        // send a new tx to settle the previous epoch
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(100000000, test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(move_tick, test_sui, c, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, sender);
        let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
        assert!(movescription::tick(&first_inscription) == std::ascii::string(b"MOVE"), 1);
        first_inscription
    }

    fun settle_epoch(scenario: &mut Scenario, test_tick_record: &mut TickRecordV2, sender: address, c: &mut clock::Clock) {
        clock::increment_for_testing(c, movescription::epoch_duration_ms() + 1);

        // send a new tx to settle the previous epoch
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(test_tick_record, test_sui, c, test_scenario::ctx(scenario));
        };
    }
}