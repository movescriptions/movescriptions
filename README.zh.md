# Movescriptions

[English](README.md)|中文

## 动机

受到 Bitcoin 上的 [铭文(Ordinals Inscription)协议](https://docs.ordinals.com/)，以及其衍生协议 [BRC20](https://layer1.gitbook.io/layer1-foundation/protocols/brc-20/documentation)的启发，Movescriptions 协议旨在利用 Move 智能合约语言，为 Inscription 提供更高级的智能化处理。我们的目标是充分利用 Move 的资源表达能力，以提升和扩展 Inscription 协议的功能，我们可以称之为 **智能铭文**。

## Inscription 的启示

Inscription 协议提供了两个关键启示，指引我们的创新方向：

1. 技术视角：Inscription 结合 BRC20 提供了一种基于数据结构模式的半同质化资产表达方式，不同于 Solidity 上基于接口的资产表达方式。
2. 生态视角：关键在于提供公平的启动方式，让用户能够参与并受益。

## 方案概述

Movescriptions 协议的核心包括：

1. 通过 Move 语言表达半同质化资产。
2. 实现具有可扩展性的公平分发机制。

## Prototype Code

下面是 Movescriptions 协议的原型代码。请注意，不同的 Move 公链可能需要不同的实现方式。

* [aptos](./aptos/)
* [sui](./sui/)
* [starcoin](./starcoin/)
* [rooch](./rooch/)


## 贡献指南

我们欢迎社区成员对 Movescriptions 协议的贡献。如果您有兴趣参与开发或提供改进建议，请在 GitHub 上直接提交 PR 或 issue。