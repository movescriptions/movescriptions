#[test_only]
module smartinscription::mint_get_factory_scenario_test {
    use std::option;
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::transfer;
    use sui::test_scenario;
    use smartinscription::movescription;
    use smartinscription::mint_get_factory;
    use smartinscription::tick_factory;
    use smartinscription::scenario_test;

    #[test]
    #[lint_allow(self_transfer)]
    public fun test_whole_process() {

        let sender = @0xABBA;
       
        let test_tick_mint_with_sui = b"TEST_MINT_GET_WITH_SUI";
        let test_tick_mint_with_move = b"TEST_MINT_GET_WITH_MOVE";

        let scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;
       
        let total_supply = 210001;
        let amount_per_mint = 10000;
        let init_locked_sui = 10;
        let init_locked_move = 10;

        
        let (clock, deploy_record, tick_tick_record, move_tick_record) = scenario_test::init_for_testing(scenario);
    
        test_scenario::next_tx(scenario, sender);
        let test_mint_with_sui_record = {
            let locked_move = movescription::new_movescription_for_testing(tick_factory::init_locked_move(), std::ascii::string(b"MOVE"), sui::balance::zero(), option::none(), test_scenario::ctx(scenario));
            let tick_name = tick_factory::do_mint(&mut tick_tick_record,locked_move, test_tick_mint_with_sui, &clock, test_scenario::ctx(scenario));
            mint_get_factory::do_deploy(&mut deploy_record, &mut tick_tick_record, tick_name, total_supply, amount_per_mint, init_locked_sui, 0, &clock, test_scenario::ctx(scenario));
            
            test_scenario::next_tx(scenario, sender);
            test_scenario::take_shared<movescription::TickRecordV2>(scenario)
        };

        test_scenario::next_tx(scenario, sender);
        {
            let test_sui = coin::mint_for_testing<SUI>(init_locked_sui+1, test_scenario::ctx(scenario));
            let ms = mint_get_factory::do_mint_with_sui(&mut test_mint_with_sui_record, test_sui,test_scenario::ctx(scenario));
            assert!(movescription::amount(&ms) == amount_per_mint, 1);
            assert!(movescription::acc(&ms) == init_locked_sui, 2);
            transfer::public_transfer(ms, sender);
        };

        //mint all
        while(true){
            test_scenario::next_tx(scenario, sender);
            {
                if (movescription::tick_record_v2_remain(&test_mint_with_sui_record) == 0) {
                    assert!(movescription::tick_record_v2_current_supply(&test_mint_with_sui_record) == total_supply, 1);
                    break
                };
                let test_sui = coin::mint_for_testing<SUI>(init_locked_sui, test_scenario::ctx(scenario));
                mint_get_factory::mint_with_sui(&mut test_mint_with_sui_record, test_sui, test_scenario::ctx(scenario));
            };
        };

        test_scenario::next_tx(scenario, sender);
        let test_mint_with_move_record = {
            let locked_move = movescription::new_movescription_for_testing(tick_factory::init_locked_move(), std::ascii::string(b"MOVE"), sui::balance::zero(), option::none(), test_scenario::ctx(scenario));
            let tick_name = tick_factory::do_mint(&mut tick_tick_record,locked_move, test_tick_mint_with_move, &clock, test_scenario::ctx(scenario));
            mint_get_factory::do_deploy(&mut deploy_record, &mut tick_tick_record, tick_name, total_supply, amount_per_mint, 0, init_locked_move, &clock, test_scenario::ctx(scenario));
            
            test_scenario::next_tx(scenario, sender);
            test_scenario::take_shared<movescription::TickRecordV2>(scenario)
        };

        //let move_tick_scription = scenario_test::mint_move_tick(scenario, &mut move_tick_record, sender, &mut clock);
        test_scenario::next_tx(scenario, sender);
        {
            let locked_move = movescription::new_movescription_for_testing(init_locked_move, std::ascii::string(b"MOVE"), sui::balance::zero(), option::none(), test_scenario::ctx(scenario));
            let ms = mint_get_factory::do_mint_with_move(&mut test_mint_with_move_record, locked_move,test_scenario::ctx(scenario));
            assert!(movescription::amount(&ms) == amount_per_mint, 1);
            assert!(movescription::amount(movescription::borrow_locked(&ms)) == init_locked_move, 2);
            transfer::public_transfer(ms, sender);
        };

        //mint all
        while(true){
            test_scenario::next_tx(scenario, sender);
            {
                if (movescription::tick_record_v2_remain(&test_mint_with_move_record) == 0) {
                    assert!(movescription::tick_record_v2_current_supply(&test_mint_with_move_record) == total_supply, 1);
                    break
                };
                let locked_move = movescription::new_movescription_for_testing(init_locked_move, std::ascii::string(b"MOVE"), sui::balance::zero(), option::none(), test_scenario::ctx(scenario));
                mint_get_factory::mint_with_move(&mut test_mint_with_move_record, locked_move, test_scenario::ctx(scenario));
            };
        };

        test_scenario::return_shared(test_mint_with_sui_record);
        test_scenario::return_shared(test_mint_with_move_record);
        
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(deploy_record);
        test_scenario::return_shared(tick_tick_record);
        test_scenario::return_shared(move_tick_record);
        test_scenario::end(scenario_val);
    }

    

}