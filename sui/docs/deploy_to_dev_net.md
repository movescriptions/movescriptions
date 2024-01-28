# Deploy to devnet

## Prerequisites
1. Install sui client
2. Clone movescriptions repo
```bash
git clone https://github.com/movescriptions/movescriptions.git
cd movescriptions/sui
```

## Deploy sui contract

1. Switch to devnet
```bash
sui client switch --env devnet
```
2. Get active address and get some SUI as Gas
```bash
sui client active-address
# copy address and get Gas from the wallet or discord
# check gas
sui client gas
```
3. Deploy sui contract
```bash
sui client publish --skip-dependency-verification --gas-budget 100000000  .
```

4. Init movescription protocol
Get the package id and deploy record id from the previous step
```bash
sui client call --package YOUR_PACKAGE_ID --module init --function init_protocol --gas-budget 1000000000 --args YOUR_DEPLOY_RECORD_ID
```

5. Mint MOVE & TICK & NAME
Get the MOVE, TICK, NAME TickRecordV2 id from the previous step

Mint MOVE

```bash
sui client call --package YOUR_PACKAGE_ID --module epoch_bus_factory --function mint --gas-budget 10000000 --args MOVE_TICK_RECORD_V2_ID --args YOUR_GAS_OBJECT_ID --args 0x6
#wait a epoch
sleep 61
sui client call --package YOUR_PACKAGE_ID --module epoch_bus_factory --function mint --gas-budget 10000000 --args MOVE_TICK_RECORD_V2_ID --args YOUR_GAS_OBJECT_ID --args 0x6
```

Mint TICK
Get the MOVE movescription id from the previous step

```bash
sui client call --package YOUR_PACKAGE_ID --module tick_factory --function mint --gas-budget 1000000000 --args TICK_TICK_RECORD_V2_ID --args YOUR_MOVE_MOVESCRIPTION_ID --args YOUR_TICK_NAME --
args 0x6
```

Deploy YOUR_TICK_NAME
Get the TICK movescription id from the previous step

```bash
sui client call --package YOUR_PACKAGE_ID --module mint_get_factory --function deploy --gas-budget 1000000000 --args YOUR_DEPLOY_RECORD_ID --args TICK_TICK_RECORD_V2_ID --args TICK_MOVESCRIPTIONI_ID --args 21000000 --args 10000 --args 0 --args 0 --args 0x6
```

Mint YOUR_TICK_NAME movescription
Get YOUR_TICK_NAME TickRecordV2 id from the previous step

```bash
sui client call --package YOUR_PACKAGE_ID --module mint_get_factory --function mint --gas-budget 1000000000 --args YOUR_TICK_NAME_TICK_RECORD_V2_ID
```
