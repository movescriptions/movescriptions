#[test_only]
module smartinscription::epoch_bus_factory_scenario_test {
    use std::option;
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::transfer;
    use sui::test_scenario::{Self, Scenario};
    use smartinscription::movescription::{Self, Movescription, TickRecordV2};
    use smartinscription::epoch_bus_factory;
    use smartinscription::tick_factory;
    use smartinscription::scenario_test;

    #[test]
    #[lint_allow(self_transfer)]
    public fun test_whole_process() {

        let admin = @0xABBA;
        // let usera = @0x1234;
        // let non_coin_holder = @0x5678;
        // let black_hole = @0x0000;
        let test_tick = b"EPOCH_BUS_TEST";

        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        let epoch_count = movescription::min_epochs();
        let total_supply = 21000000;
        let epoch_amount = total_supply / epoch_count;
        
        let (clock, deploy_record, tick_tick_record, move_tick_record) = scenario_test::init_for_testing(scenario);

        let move_tick_scription = mint_move_tick(scenario, &mut move_tick_record, admin, &mut clock);

        test_scenario::next_tx(scenario, admin);
        let test_tick_record = {
            let now_ms = clock::timestamp_ms(&clock);
            let tick_name = tick_factory::do_mint(&mut tick_tick_record,move_tick_scription, test_tick, &clock, test_scenario::ctx(scenario));
            epoch_bus_factory::do_deploy(&mut deploy_record, &mut tick_tick_record, tick_name, total_supply, 1000, now_ms, epoch_count, &clock, test_scenario::ctx(scenario));
            
            test_scenario::next_tx(scenario, admin);
            test_scenario::take_shared<movescription::TickRecordV2>(scenario)
        };

        test_scenario::next_tx(scenario, admin);
        {
            let test_sui = coin::mint_for_testing<SUI>(1001, test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(&mut test_tick_record, test_sui, &clock, test_scenario::ctx(scenario));
        };

        settle_epoch(scenario, &mut test_tick_record, admin, &mut clock);
        
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

        settle_epoch(scenario, &mut test_tick_record, admin, &mut clock);

        while(true){
            test_scenario::next_tx(scenario, admin);
            {
                if (movescription::tick_record_v2_remain(&test_tick_record) == 0) {
                    assert!(movescription::tick_record_v2_current_supply(&test_tick_record) == total_supply, 1);
                    //assert!(movescription::tick_record_v2_current_epoch(&test_tick_record) == movescription::tick_record_v2_epoch_count(&test_tick_record)-1, 2);
                    break
                };
                let test_sui = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
                epoch_bus_factory::do_mint(&mut test_tick_record,test_sui, &clock, test_scenario::ctx(scenario));
            };

            settle_epoch(scenario, &mut test_tick_record, admin, &mut clock); 
        };

        //test burn
        test_scenario::next_tx(scenario, admin);
        {
            let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
            let amount = movescription::amount(&first_inscription);
            let acc = movescription::acc(&first_inscription);
            let tick = movescription::tick(&first_inscription);
            let (coin, locked_movescription, receipt) = movescription::do_burn_for_receipt_v2(&mut test_tick_record, first_inscription, b"love and peace", test_scenario::ctx(scenario));
            option::destroy_none(locked_movescription);
            assert!(coin::value(&coin) == acc, 1);
            transfer::public_transfer(coin, admin);
            let (burn_tick, burn_amount) = movescription::drop_receipt(receipt);
            assert!(tick == burn_tick, 2);
            assert!(amount == burn_amount, 3);
            assert!(movescription::tick_record_v2_current_supply(&test_tick_record) == total_supply - amount, 4);
        };

        test_scenario::return_shared(test_tick_record);
        
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(deploy_record);
        test_scenario::return_shared(tick_tick_record);
        test_scenario::return_shared(move_tick_record);
        test_scenario::end(scenario_val);
    }

    fun mint_move_tick(scenario: &mut Scenario, move_tick_record: &mut movescription::TickRecordV2, sender: address, c: &mut clock::Clock) : Movescription{
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(100000000, test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(move_tick_record, test_sui, c, test_scenario::ctx(scenario));
        };
        clock::increment_for_testing(c, movescription::epoch_duration_ms() + 1);

        // send a new tx to settle the previous epoch
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(100000000, test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(move_tick_record, test_sui, c, test_scenario::ctx(scenario));
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