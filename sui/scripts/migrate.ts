import { loadSync } from "https://deno.land/std/dotenv/mod.ts"
import { getFullnodeUrl, SuiClient } from 'npm:@mysten/sui.js/client';
import { Ed25519Keypair } from 'npm:@mysten/sui.js/keypairs/ed25519';
import { TransactionBlock } from 'npm:@mysten/sui.js/transactions';

const env = loadSync();
const secret_key_mnemonics = env.SECRET_KEY_ED25519_1_MNEMONICS;
const keypair = Ed25519Keypair.deriveKeypair(secret_key_mnemonics);
console.log(keypair.getPublicKey().toSuiAddress())

const client = new SuiClient({
	url: getFullnodeUrl('mainnet'),
});

const PACKAGE_ID = env.PACKAGE_ID;
const deploy_id: string = env.DEPLOY_RECORD;

const getSuiDynamicFields = async (
    id: string,
    dynamic_field_name: string,
) => {
    const parent_obj = await client.getObject({
        id,
        options: {
            showContent: true,
        },
    })
    const dynamic_field_key =
    // @ts-ignore
    parent_obj.data?.content?.fields[dynamic_field_name].fields.id.id ?? ''
    if (!dynamic_field_key) {
        throw new Error(`${dynamic_field_name} not found`)
    }
  
    const collection_keys = await client.getDynamicFields({
        parentId: dynamic_field_key,
    })
    const result = []
    for (const key of collection_keys.data) {
        const obj = await getSuiObject(key.objectId)
        // @ts-ignore
        const real_obj = await getSuiObject(obj.data?.content?.fields.value)
        // @ts-ignore
        result.push(real_obj.data?.content?.fields)
    }
    return result
}

const getSuiObject = (id: string) => {
    return client.getObject({
        id,
        options: {
            showContent: true,
        },
    })
}

// get tick records informations
const ticks = await getSuiDynamicFields(deploy_id, 'record')


const txb = new TransactionBlock();
// update deploy record id
txb.moveCall({
	target: `${PACKAGE_ID}::movescription::migrate_deploy_record`,
	arguments: [txb.object(deploy_id)],
});
// update tick record id
ticks.forEach(item => {
    txb.moveCall({
        target: `${PACKAGE_ID}::movescription::migrate_tick_record`,
        arguments: [txb.object(item['id']['id'])],
    });
});

txb.setSender(keypair.getPublicKey().toSuiAddress());

const result = await client.signAndExecuteTransactionBlock({
	transactionBlock: txb,
	signer: keypair,
	requestType: 'WaitForLocalExecution',
	options: {
		showEffects: true,
	},
});