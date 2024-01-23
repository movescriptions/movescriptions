#[test_only]
module smartinscription::tick_factory_scenario_test {
    use std::option;
    use sui::clock;
    use sui::sui::SUI;
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use sui::test_scenario;
    use smartinscription::movescription::{Self, Movescription, TickRecordV2};
    use smartinscription::tick_factory;
    use smartinscription::content_type;

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

        let c = clock::create_for_testing(test_scenario::ctx(scenario));
        let start_time_ms = movescription::protocol_start_time_ms();
        
        clock::increment_for_testing(&mut c, start_time_ms);

        test_scenario::next_tx(scenario, admin);
        let move_tick = {
            movescription::init_for_testing(test_scenario::ctx(scenario));
            //Need to start a new tx to get the shared object
            test_scenario::next_tx(scenario, admin);
            test_scenario::take_shared<movescription::TickRecord>(scenario)
        };

        test_scenario::next_tx(scenario, admin);
        {
            let deploy_record = test_scenario::take_shared<movescription::DeployRecord>(scenario);
            tick_factory::deploy(&mut deploy_record, test_scenario::ctx(scenario));
            test_scenario::return_shared(deploy_record);
        };

        test_scenario::next_tx(scenario, usera);
        {
            //Mint the TICK movescription, register the TEST tick name
            let tick_name_tick_record = test_scenario::take_shared<movescription::TickRecordV2>(scenario);
            let test_sui = coin::mint_for_testing<SUI>(tick_factory::init_locked_sui(), test_scenario::ctx(scenario));
            tick_factory::mint(&mut tick_name_tick_record, test_sui, test_tick_name, &c, test_scenario::ctx(scenario)); 
            test_scenario::return_shared(tick_name_tick_record); 
        };
        
        test_scenario::next_tx(scenario, usera);
        {
            let first_inscription = test_scenario::take_from_sender<Movescription>(scenario);
            assert!(movescription::amount(&first_inscription) == 1, 1);
            //std::debug::print(&first_inscription);
            assert!(std::ascii::into_bytes(movescription::tick(&first_inscription)) == tick_factory::tick(), 2);
            let metadata_opt = movescription::metadata(&first_inscription);
            assert!(option::is_some(&metadata_opt), 3);
            let metadata = option::destroy_some(metadata_opt);
            assert!(content_type::is_text(&movescription::metadata_content_type(&metadata)), 4);
            assert!(movescription::metadata_content(&metadata) == test_tick_name, 5);
            
            //deploy the TEST tick
            let deploy_record = test_scenario::take_shared<movescription::DeployRecord>(scenario);
            let tick_record = movescription::do_deploy_with_witness(&mut deploy_record, first_inscription, test_tick_total_supply, 0, WITNESS{}, test_scenario::ctx(scenario));
            let test_ms = mint_test_ms(&mut tick_record,1, test_scenario::ctx(scenario));
            assert!(movescription::check_tick(&test_ms, test_tick_name), 6);
            transfer::public_transfer(test_ms, usera);
            transfer::public_share_object(tick_record);
            test_scenario::return_shared(deploy_record);
        };

        test_scenario::next_tx(scenario, usera);
       
        test_scenario::return_shared(move_tick);
        clock::destroy_for_testing(c);
        test_scenario::end(scenario_val);
    }
    
    #[test_only]
    fun mint_test_ms(tick_record: &mut TickRecordV2, amount: u64, ctx: &mut TxContext) : Movescription{
        movescription::do_mint_with_witness(tick_record, coin::zero<SUI>(ctx), amount, option::none(), WITNESS{}, ctx)
    }
}