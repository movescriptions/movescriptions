# Movescriptions on Rooch

## Test

1. Install rooch

```bash
cargo install --path .
cargo install --git https://github.com/rooch-network/rooch rooch 
```

2. Start server

```bash
rooch server start
```

3. Deply Modules

```bash
rooch move publish --named-addresses movescriptions=default
```

4. Deploy MRC20

```bash
rooch move run --function default::mrc20::deploy --args object:default::movescription::TickRegistry --args object:default::mrc20::MRC20Store --args string:move --args u64:2 --args u256:21000000 --args u256:1000 --args u64:18
```

5. Get PoW input

```bash
rooch move view --function default::movescription::pow_input --args address:default --args string:move --args u256:1000 
```
```json
{
  "vm_status": "Executed",
  "return_values": [
    {
      "value": {
        "type_tag": "vector<u8>",
        "value": "0x4c6d6f7665e8030000000000000000000000000000000000000000000000000000000000005078ae74bac281e65fc446b467a843b186904a1b2d435f367030fc755eef10810200000000000000"
      },
      "decoded_value": "0x6d6f7665e8030000000000000000000000000000000000000000000000000000000000005078ae74bac281e65fc446b467a843b186904a1b2d435f367030fc755eef10810200000000000000"
    }
  ]
}
```

6. Calculate PoW

```bash
movescription pow -i 0x6d6f7665e8030000000000000000000000000000000000000000000000000000000000005078ae74bac281e65fc446b467a843b186904a1b2d435f367030fc755eef10810200000000000000 -d 2
Nonce: 100000difficulty: 2, hash: 0000ba3600fc7f2276c11b1c1bf207dc263493a40f4e70d2021784e8652c797c, nonce: 170095, use millis: 101
```

Validate the nonce
```bash
rooch move view --function default::movescription::validate_pow --args address:default --args string:move --args u256:1000 --args u64:2 --args u64:170095
```
```json
{
  "vm_status": "Executed",
  "return_values": [
    {
      "value": {
        "type_tag": "bool",
        "value": "0x01"
      },
      "decoded_value": true
    }
  ]
}
```

5. Mint MRC20

```bash
rooch move run --function default::mrc20::mint --args object:default::mrc20::MRC20Store --args string:move --args u64:170095 --args u256:1000 
```

6. Query state

Get the active account address

```bash
rooch account list 
```

Query the state via `rooch_queryGlobalStates`

```bash
rooch rpc request --method rooch_queryGlobalStates --params '[{"object_type":"${your_active_account_address}::movescription::Movescription"},null, "200", true]' 
```
```json
{
  "data": [
    {
      "object_id": "0x99891854b64a32266444c444a4ad8ace2fcdb0372178eea65e6f3c4806a18def",
      "owner": "0x5078ae74bac281e65fc446b467a843b186904a1b2d435f367030fc755eef1081",
      "flag": 0,
      "value": {
        "abilities": 12,
        "type": "0x5078ae74bac281e65fc446b467a843b186904a1b2d435f367030fc755eef1081::movescription::Movescription",
        "value": {
          "metadata": {
            "abilities": 7,
            "type": "0x1::option::Option<0x5078ae74bac281e65fc446b467a843b186904a1b2d435f367030fc755eef1081::movescription::Metadata>",
            "value": {
              "vec": []
            }
          },
          "tick": "move",
          "value": "1000"
        }
      },
      "object_type": "0x5078ae74bac281e65fc446b467a843b186904a1b2d435f367030fc755eef1081::movescription::Movescription",
      "key_type": null,
      "size": 0,
      "tx_order": 2,
      "state_index": 0,
      "created_at": 0,
      "updated_at": 0
    }
  ],
  "next_cursor": {
    "tx_order": 2,
    "state_index": 0
  },
  "has_next_page": false
}
```