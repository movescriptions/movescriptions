#[test_only]
module smartinscription::movescription_object_test{
    use std::ascii::{string, String};
    use std::option;
    use sui::sui::SUI;
    use sui::coin;
    use sui::tx_context::{Self, TxContext};
    use sui::balance;
    use smartinscription::movescription::{Self, Movescription};

    #[test_only]
    struct WITNESS has drop {}

    #[test]
    fun test_calculate_deploy_fee(){
        let fee = movescription::calculate_deploy_fee(b"MOVE", movescription::base_epoch_count());
        assert!(fee == 1100, 0);
        let fee = movescription::calculate_deploy_fee(b"MOVER", movescription::base_epoch_count());
        assert!(fee == 900, 0);
        let fee = movescription::calculate_deploy_fee(b"MMMMMMMMMMMMMMMMMMMMMMMMMMMMOVER", movescription::base_epoch_count());
        assert!(fee == 225, 0);
        let fee = movescription::calculate_deploy_fee(b"MOVE", 60*24);
        //std::debug::print(&fee);
        assert!(fee == 2500, 0);
        let fee = movescription::calculate_deploy_fee(b"MOVE", movescription::min_epochs());
        assert!(fee == 19000, 0); 
        //std::debug::print(&fee);
    }

     #[test]
    fun test_split_acc(){
        let acc_balance = balance::create_for_testing<SUI>(1000u64);
        let split_amount = 100u64;
        let inscription_amount = 1000u64;
        let tick = string(b"MOVE");
        let tx_context = tx_context::dummy();
        let ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        let new_ms = movescription::do_split(&mut ms, split_amount, &mut tx_context);
        let new_acc_amount = movescription::acc(&new_ms);
        assert!(new_acc_amount == 100u64, 0);
        movescription::drop_movescription_for_testing(ms);
        movescription::drop_movescription_for_testing(new_ms);
    }

    #[test]
    fun test_split_acc2(){
        let acc_balance = balance::create_for_testing<SUI>(4_0000_0000u64);
        let split_amount = 1111_1111u64;
        let inscription_amount = 9999_9999u64;
        let tick = string(b"MOVE");
        let tx_context = tx_context::dummy();
        let ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        let new_ms = movescription::do_split(&mut ms, split_amount, &mut tx_context);
        let new_acc_amount = movescription::acc(&new_ms);
        assert!(new_acc_amount == 4444_4444u64, 0);
        movescription::drop_movescription_for_testing(ms);
        movescription::drop_movescription_for_testing(new_ms);
    }

    #[test]
    fun test_split_acc3(){
        let acc_balance = balance::create_for_testing<SUI>(100u64);
        let split_amount = 1u64;
        let inscription_amount = 100_0000u64;
        let tick = string(b"MOVE");
        let tx_context = tx_context::dummy();
        let ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        let new_ms = movescription::do_split(&mut ms, split_amount, &mut tx_context);
        let new_acc_amount = movescription::acc(&new_ms);
        //std::debug::print(&new_acc_amount);
        assert!(new_acc_amount == 1u64, 0);
        movescription::drop_movescription_for_testing(ms);
        movescription::drop_movescription_for_testing(new_ms);
    }

    #[test]
    fun test_merge(){
        let tick = string(b"MOVE");
        let tx_context = tx_context::dummy();
        let first_acc_balance = balance::create_for_testing<SUI>(50u64);
        let first_amount = 100u64;
        let first_ms = movescription::new_movescription_for_testing(first_amount, tick, first_acc_balance, option::none(), &mut tx_context);
        let second_acc_balance = balance::create_for_testing<SUI>(50u64);
        let second_amount = 200u64;
        let second_ms = movescription::new_movescription_for_testing(second_amount, tick, second_acc_balance, option::none(), &mut tx_context);
        movescription::do_merge(&mut first_ms, second_ms);
        let new_amount = movescription::amount(&first_ms);
        assert!(new_amount == first_amount+second_amount, 0);

        let new_acc_amount = movescription::acc(&first_ms);
        assert!(new_acc_amount == 100u64, 0);

        movescription::drop_movescription_for_testing(first_ms);
    }

    #[test]
    #[expected_failure]
    fun test_merge_different_movescription_failed(){
        let tick1 = string(b"MOVE");
        let tick2 = string(b"M0VE");
        let tx_context = tx_context::dummy();
        let first_acc_balance = balance::create_for_testing<SUI>(50u64);
        let first_amount = 100u64;
        let first_ms = movescription::new_movescription_for_testing(first_amount, tick1, first_acc_balance, option::none(), &mut tx_context);
        let second_acc_balance = balance::create_for_testing<SUI>(50u64);
        let second_amount = 200u64;
        let second_ms = movescription::new_movescription_for_testing(second_amount, tick2, second_acc_balance, option::none(), &mut tx_context);
        movescription::do_merge(&mut first_ms, second_ms);
        movescription::drop_movescription_for_testing(first_ms);
    } 

    #[test]
    fun test_check_tick(){
        let tick = string(b"MOVE");
        let tx_context = tx_context::dummy();
        let acc_balance = balance::create_for_testing<SUI>(50u64);
        let amount = 100u64;
        let ms = movescription::new_movescription_for_testing(amount, tick, acc_balance, option::none(), &mut tx_context);
        assert!(movescription::check_tick(&ms, b"MOVE"), 0);
        movescription::drop_movescription_for_testing(ms);
    }

    #[test]
    #[expected_failure]
    fun test_check_tick_failed(){
        let tick = string(b"MOVE");
        let tx_context = tx_context::dummy();
        let acc_balance = balance::create_for_testing<SUI>(50u64);
        let amount = 100u64;
        let ms = movescription::new_movescription_for_testing(amount, tick, acc_balance, option::none(), &mut tx_context);
        assert!(movescription::check_tick(&ms, b"MAVE"), 0);
        movescription::drop_movescription_for_testing(ms);
    }

    #[test]
    fun test_lock_and_burn(){
        let tx_context = tx_context::dummy();

        let tick = string(b"MOVE");
        let tick_record = movescription::new_tick_record_for_testing<WITNESS>(tick, 1000000, 10000, WITNESS{},&mut tx_context);
        
        let amount = 100u64;
        let acc_balance = 50;
        let move_ms = new_test_movescription(tick, amount, acc_balance, &mut tx_context);
        
        let test_ms = new_test_movescription(string(b"TEST"), amount, acc_balance, &mut tx_context);
        movescription::lock_within(&mut move_ms, test_ms);

        let (coin, locked_movescription) = movescription::do_burn_v2(&mut tick_record, move_ms, &mut tx_context);
        assert!(option::is_some(&locked_movescription), 0);
        let locked_movescription = option::destroy_some(locked_movescription);
        let locked_amount = movescription::amount(&locked_movescription);
        assert!(locked_amount == amount, 0);
        coin::burn_for_testing(coin);
        movescription::drop_movescription_for_testing(locked_movescription);
        movescription::drop_tick_record_for_testing(tick_record);
    }

    #[test]
    fun test_lock_and_split(){
        let tx_context = tx_context::dummy();

        let tick = string(b"MOVE");
        
        let amount = 100u64;
        let acc_balance = 50;
        let move_ms = new_test_movescription(tick, amount, acc_balance, &mut tx_context);
        
        let test_ms = new_test_movescription(string(b"TEST"), amount, acc_balance, &mut tx_context);
        movescription::lock_within(&mut move_ms, test_ms);

        let new_movescription = movescription::do_split(&mut move_ms, 50, &mut tx_context);
        assert!(movescription::contains_locked(&new_movescription), 0);

        let locked_movescription = movescription::borrow_locked(&new_movescription);
        let locked_amount = movescription::amount(locked_movescription);

        assert!(locked_amount == 50, 0);
        movescription::drop_movescription_for_testing(move_ms);
        movescription::drop_movescription_for_testing(new_movescription);
    }

    #[test]
    fun test_lock_and_merge(){
        let tx_context = tx_context::dummy();

        let tick = string(b"MOVE");
        
        let amount = 100u64;
        let acc_balance = 50;
        let move_ms1 = new_test_movescription(tick, amount, acc_balance, &mut tx_context);
        
        let test_ms1 = new_test_movescription(string(b"TEST"), amount, acc_balance, &mut tx_context);
        movescription::lock_within(&mut move_ms1, test_ms1);


        let move_ms2 = new_test_movescription(tick, amount, acc_balance, &mut tx_context);
        
        let test_ms2 = new_test_movescription(string(b"TEST"), amount, acc_balance, &mut tx_context);
        movescription::lock_within(&mut move_ms2, test_ms2);

        movescription::do_merge(&mut move_ms1, move_ms2);

        let locked_movescription = movescription::borrow_locked(&move_ms1);
        let locked_amount = movescription::amount(locked_movescription);

        assert!(locked_amount == 200, 0);
        movescription::drop_movescription_for_testing(move_ms1);
    }

    #[test_only]
    fun new_test_movescription(tick: String, amount: u64, acc: u64, ctx: &mut TxContext) : Movescription{
        let acc_balance = balance::create_for_testing<SUI>(acc); 
        movescription::new_movescription_for_testing(amount, tick, acc_balance, option::none(), ctx)
    }
}