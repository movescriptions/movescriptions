#[test_only]
module smartinscription::scenario_test{
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin;
    use sui::sui::SUI;
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2, Movescription};
    use smartinscription::tick_factory;
    use smartinscription::epoch_bus_factory;

    #[test_only]
    /// init the movescription and return DeployRecord, TICK TickRecord, MOVE TickRecord
    public fun init_for_testing(scenario: &mut Scenario) : (Clock, DeployRecord, TickRecordV2, TickRecordV2) {
        let sender = @smartinscription;
        test_scenario::next_tx(scenario,sender);

        let c = clock::create_for_testing(test_scenario::ctx(scenario));
        let start_time_ms = movescription::protocol_start_time_ms();
        clock::increment_for_testing(&mut c, start_time_ms);

        let deploy_record = {
            movescription::init_for_testing(test_scenario::ctx(scenario));
            //Need to start a new tx to get the shared object
            test_scenario::next_tx(scenario, sender);
            test_scenario::take_shared<DeployRecord>(scenario)
        };
        let tick_tick_record = {
            tick_factory::deploy_tick_tick(&mut deploy_record, test_scenario::ctx(scenario));
            test_scenario::next_tx(scenario, sender);
            test_scenario::take_shared<TickRecordV2>(scenario)
        };
        let move_tick_record = {
            epoch_bus_factory::deploy_move_tick(&mut deploy_record, test_scenario::ctx(scenario));
            test_scenario::next_tx(scenario, sender);
            test_scenario::take_shared<TickRecordV2>(scenario)
        };
        (c, deploy_record, tick_tick_record, move_tick_record)
    }

    #[test_only]
    public fun mint_move_tick(scenario: &mut Scenario, move_tick_record: &mut movescription::TickRecordV2, sender: address, c: &mut clock::Clock) : Movescription{
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(epoch_bus_factory::init_locked_sui_of_move(), test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(move_tick_record, test_sui, c, test_scenario::ctx(scenario));
        };
        clock::increment_for_testing(c, movescription::epoch_duration_ms() + 1);

        // send a new tx to settle the previous epoch
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(epoch_bus_factory::init_locked_sui_of_move(), test_scenario::ctx(scenario));
            epoch_bus_factory::do_mint(move_tick_record, test_sui, c, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, sender);
        let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
        assert!(movescription::tick(&first_inscription) == std::ascii::string(b"MOVE"), 1);
        first_inscription
    }
}