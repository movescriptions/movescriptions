# SFT交易接口

依照SFT(Semi Fungible Token)标准，在每次交易时，会抽取一部分交易费注入到铭文中去。比例由交易所自定义，建议是交易手续费的10%~20%.
这个功能需要集成到交易所的合约代码去实现。

## 配置

在`Move.toml`中添加配置。
```toml
[package]
name = "market"
version = "0.0.1"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/mainnet" }
SmartInscription = { git = "https://github.com/movescriptions/movescriptions.git", subdir = "sui", rev = "main"}

[addresses]
market = "0x0"
smartinscription= "0x2670cf9d9c9ca2b63581ccfefcf3cb64837d878b24ca86928e05ecd3f3d82488"
```

最新 smartinscription 的 PackageID 可以在 [README.md](../README.md) 中查找。

## 合约调用

在合约`module`中引用。
```rust
use smartinscription::movescription::inject_sui;
```

inject_sui 函数的实现。
```rust
public fun inject_sui(inscription: &mut Movescription, receive: Coin<SUI>) {
    coin::put(&mut inscription.acc, receive);
}
```

使用方法示例:

```rust
let inscription: Movescription = GetMovescriptionExample();
let fee: Coin<SUI> = GetFromSomeWhere();
inject_sui(&mut inscription, fee);
```
