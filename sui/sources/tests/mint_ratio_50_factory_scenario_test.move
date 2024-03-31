#[test_only]
module smartinscription::mint_ratio_50_factory_scenario_test {
    use std::option;
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::transfer;
    use sui::test_scenario;
    use smartinscription::movescription;
    use smartinscription::mint_ratio_50_factory;
    use smartinscription::tick_factory;
    use smartinscription::scenario_test;

    #[test]
    #[lint_allow(self_transfer)]
    public fun test_whole_process() {

        let sender = @0xABBA;
       
        let test_tick = b"ALOHA";

        let scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;
       
        let total_supply = 3_000_000;
        let amount_per_sui  = 300_000;
        let min_value_sui =   1_000_000_000;
        let max_value_sui = 500_000_000_000;


        
        let (clock, deploy_record, tick_tick_record, move_tick_record) = scenario_test::init_for_testing(scenario);
    
        test_scenario::next_tx(scenario, sender);
        let test_mint_with_sui_record = {
            let locked_move = movescription::new_movescription_for_testing(tick_factory::init_locked_move(), std::ascii::string(b"MOVE"), sui::balance::zero(), option::none(), test_scenario::ctx(scenario));
            let tick_name = tick_factory::do_mint(&mut tick_tick_record,locked_move, test_tick, &clock, test_scenario::ctx(scenario));
            mint_ratio_50_factory::do_deploy(&mut deploy_record, &mut tick_tick_record, tick_name, total_supply, amount_per_sui, 0, min_value_sui, max_value_sui, &clock, test_scenario::ctx(scenario));
            
            test_scenario::next_tx(scenario, sender);
            test_scenario::take_shared<movescription::TickRecordV2>(scenario)
        };
        clock::increment_for_testing(&mut clock, 1);
        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(min_value_sui, test_scenario::ctx(scenario));
            let ms = mint_ratio_50_factory::do_mint_v2(&mut test_mint_with_sui_record, &mut test_sui, &clock, test_scenario::ctx(scenario));
            assert!(movescription::amount(&ms) == 300_000, 1);
            assert!(movescription::acc(&ms) == min_value_sui, 2);
            transfer::public_transfer(ms, sender);
            coin::burn_for_testing<SUI>(test_sui);
        };

        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(max_value_sui, test_scenario::ctx(scenario));
            let ms = mint_ratio_50_factory::do_mint_v2(&mut test_mint_with_sui_record, &mut test_sui, &clock, test_scenario::ctx(scenario));
            assert!(movescription::amount(&ms) == 2_700_000, 1);
            assert!(movescription::acc(&ms) == 9_000_000_000, 2);
            transfer::public_transfer(ms, sender);
            coin::burn_for_testing<SUI>(test_sui);
        };

        test_scenario::return_shared(test_mint_with_sui_record);
        
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(deploy_record);
        test_scenario::return_shared(tick_tick_record);
        test_scenario::return_shared(move_tick_record);
        test_scenario::end(scenario_val);
    }

    

}