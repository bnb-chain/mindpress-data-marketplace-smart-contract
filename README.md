# mind-marketplace-contract

Mind marketplace is a marketplace protocol for safely and efficiently buying and selling data uploaded in [Greenfield](https://github.com/bnb-chain/greenfield).

## Install

To install dependencies:

```bash
git clone https://github.com/bnb-chain/mind-marketplace-contract.git && cd mind-marketplace-contract
yarn install
forge install --no-git --no-commit foundry-rs/forge-std@v1.7.1
```

## Deploy

1. Copy `.env.example` and setup `OP_PRIVATE_KEY` and `OWNER_PRIVATE_KEY` in `.env`.

```bash
cp .env.example .env
```

2. Deploy with foundry.

```bash
forge script ./script/1-deploy.s.sol --rpc-url ${RPC_TESTNET} --legacy --broadcast --private-key ${OP_PRIVATE_KEY}
```

## Test

Test with foundry after deploying:

```bash
forge test
```
