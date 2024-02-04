module smartinscription::init{
    use sui::tx_context::TxContext;
    use smartinscription::movescription::{DeployRecord};
    use smartinscription::tick_factory;
    use smartinscription::epoch_bus_factory;
    use smartinscription::name_factory;
    use smartinscription::mint_get_factory;
    

    public entry fun init_protocol(deploy_record: &mut DeployRecord, ctx: &mut TxContext){
        tick_factory::deploy_tick_tick(deploy_record, ctx);
        epoch_bus_factory::deploy_move_tick(deploy_record, ctx);
        name_factory::deploy_name_tick(deploy_record, ctx);
        mint_get_factory::deploy_test_tick(deploy_record, ctx);        
    }

}