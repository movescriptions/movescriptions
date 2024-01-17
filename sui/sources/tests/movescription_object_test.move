#[test_only]
module smartinscription::movescription_object_test{

    use std::option;
    use sui::sui::SUI;
    use sui::tx_context;
    use sui::balance;
    use sui::coin::{Self, Coin};
    use smartinscription::movescription;

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
        let tick = std::ascii::string(b"MOVE");
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
        let tick = std::ascii::string(b"MOVE");
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
        let tick = std::ascii::string(b"MOVE");
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
        let tick = std::ascii::string(b"MOVE");
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
        let tick1 = std::ascii::string(b"MOVE");
        let tick2 = std::ascii::string(b"M0VE");
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
    fun test_dof(){
        let tick = std::ascii::string(b"MOVE");
        let tx_context = tx_context::dummy();
        let acc_balance = balance::create_for_testing<SUI>(1000u64);
        let inscription_amount = 1000u64;
        let ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        let value = coin::mint_for_testing<SUI>(100u64, &mut tx_context);
        movescription::add_dof(&mut ms, value);
        assert!(movescription::exists_dof<Coin<SUI>>(&ms), 1);
        assert!(movescription::contains_dof(&ms), 2);
        assert!(movescription::attach_dof(&ms) == 1u64, 3);
        {
            let dof = movescription::borrow_dof<Coin<SUI>>(&ms);
            assert!(coin::value(dof) == 100u64, 4);
        };
        {
            let c = coin::mint_for_testing<SUI>(100u64, &mut tx_context);
            let dof = movescription::borrow_dof_mut<Coin<SUI>>(&mut ms);
            coin::join(dof, c);
        };
        let new_value = movescription::remove_dof<Coin<SUI>>(&mut ms);
        assert!(coin::value(&new_value) == 200u64, 4);

        assert!(!movescription::exists_dof<Coin<SUI>>(&ms), 5);
        assert!(!movescription::contains_dof(&ms), 6);
        assert!(movescription::attach_dof(&ms) == 0u64, 7);

        coin::burn_for_testing(new_value);
        movescription::drop_movescription_for_testing(ms);
    }

    #[test]
    #[expected_failure]
    fun test_dof_split_failed(){
        let tick = std::ascii::string(b"MOVE");
        let tx_context = tx_context::dummy();
        let acc_balance = balance::create_for_testing<SUI>(1000u64);
        let inscription_amount = 1000u64;
        let ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        let value = coin::mint_for_testing<SUI>(100u64, &mut tx_context);
        movescription::add_dof(&mut ms, value);
        let split_amount = 100u64;
        let new_ms = movescription::do_split(&mut ms, split_amount, &mut tx_context);
        movescription::drop_movescription_for_testing(ms);
        movescription::drop_movescription_for_testing(new_ms);
    }

    #[test]
    fun test_dof_merge(){
        let tick = std::ascii::string(b"MOVE");
        let tx_context = tx_context::dummy();
        let acc_balance = balance::create_for_testing<SUI>(1000u64);
        let inscription_amount = 1000u64;
        let ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        let value = coin::mint_for_testing<SUI>(100u64, &mut tx_context);
        movescription::add_dof(&mut ms, value);
        let acc_balance = balance::create_for_testing<SUI>(1000u64);
        let second_ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        movescription::do_merge(&mut ms, second_ms);
        movescription::drop_movescription_for_testing(ms);
    }

    #[test]
    #[expected_failure]
    fun test_dof_merge_failed(){
        let tick = std::ascii::string(b"MOVE");
        let tx_context = tx_context::dummy();
        let acc_balance = balance::create_for_testing<SUI>(1000u64);
        let inscription_amount = 1000u64;
        let ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        let value = coin::mint_for_testing<SUI>(100u64, &mut tx_context);
        movescription::add_dof(&mut ms, value);
        let acc_balance = balance::create_for_testing<SUI>(1000u64);
        let second_ms = movescription::new_movescription_for_testing(inscription_amount, tick, acc_balance, option::none(), &mut tx_context);
        let value = coin::mint_for_testing<SUI>(100u64, &mut tx_context);
        movescription::add_dof(&mut second_ms, value);
        movescription::do_merge(&mut ms, second_ms);
        movescription::drop_movescription_for_testing(ms);
    }
    
}