#[test_only]
module smartinscription::scenario_test{
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use smartinscription::movescription::{Self, DeployRecord, TickRecordV2};
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
}