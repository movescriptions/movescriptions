#[test_only]
module smartinscription::tick_factory_scenario_test {
    use std::option;
    use sui::clock;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use sui::test_scenario;
    use sui::balance;
    use smartinscription::movescription::{Self, Movescription, TickRecordV2};
    use smartinscription::tick_factory;
    use smartinscription::scenario_test;
    use smartinscription::epoch_bus_factory;

    #[test_only]
    struct WITNESS has drop{}

    #[test]
    #[lint_allow(self_transfer, share_owned)]
    public fun test_whole_process() {

        let admin = @0xABBA;
        let usera = @0x1234;
        let test_tick_name = b"TEST";
        let test_tick_total_supply = 100000000u64;
     
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        let (clock, deploy_record, tick_tick_record, move_tick_record) = scenario_test::init_for_testing(scenario); 

        test_scenario::next_tx(scenario, usera);
        let test_tick_name_movescription = {
            //Mint a TICK movescription, register test_tick_name 
            let locked_move = epoch_bus_factory::mint_for_testing(&mut move_tick_record, tick_factory::init_locked_move(), balance::zero(), test_scenario::ctx(scenario));
            tick_factory::do_mint(&mut tick_tick_record, locked_move, test_tick_name, &clock, test_scenario::ctx(scenario)) 
        };
        
        {
            assert!(movescription::amount(&test_tick_name_movescription) == 1, 1);
            //std::debug::print(&test_tick_name_movescription);
            assert!(std::ascii::into_bytes(movescription::tick(&test_tick_name_movescription)) == tick_factory::tick(), 2);
            let tick_name_metadata = tick_factory::decode_metadata(&test_tick_name_movescription);
            assert!(tick_factory::metadata_tick_name(&tick_name_metadata) == std::ascii::string(test_tick_name), 5);
            assert!(tick_factory::metadata_miner(&tick_name_metadata) == usera, 6);
            
            //deploy the TEST tick
            let tick_record = tick_factory::do_deploy(&mut deploy_record, &mut tick_tick_record, test_tick_name_movescription, test_tick_total_supply, true, WITNESS{}, test_scenario::ctx(scenario));
            let test_ms = mint_test_ms(&mut tick_record,1, test_scenario::ctx(scenario));
            assert!(movescription::check_tick(&test_ms, test_tick_name), 6);
            transfer::public_transfer(test_ms, usera);
            transfer::public_share_object(tick_record);
        };

        clock::destroy_for_testing(clock);
        test_scenario::return_shared(deploy_record);
        test_scenario::return_shared(tick_tick_record);
        test_scenario::return_shared(move_tick_record);
        test_scenario::end(scenario_val);
    }
    
    #[test_only]
    fun mint_test_ms(tick_record: &mut TickRecordV2, amount: u64, ctx: &mut TxContext) : Movescription{
        movescription::do_mint_with_witness(tick_record, balance::zero<SUI>(), amount, option::none(), WITNESS{}, ctx)
    }
}