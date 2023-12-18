# Movescriptions on Rooch

## Test

1. Install rooch

```bash
cargo install --git https://github.com/rooch-network/rooch rooch 
```

2. Deply Modules

```bash
rooch move publish --named-addresses movescription=default
```

3. Deploy MRC20

```bash
rooch move run --function default::movescription::deploy_mrc20 --args object:default::movescription::MovescriptionRegistry --args string:move --args u256:21000000 --args u256:1000 --args u64:18
```

3. Mint MRC20

```bash
rooch move run --function default::movescription::mint_mrc20 --args object:default::movescription::MovescriptionRegistry --args string:move --args u256:1000
```

4. Query state

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