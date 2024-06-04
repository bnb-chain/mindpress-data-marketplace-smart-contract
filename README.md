# Mind Marketplace Contract

## Overview
[MindPress Data Marketplace](https://testnet-marketplace.mindpress.io/) is a demo built on the BNB Smart Chain and BNB Greenfield storage chains. It uses the image trading scenario as an example to demonstrate the use of BNB Greenfield's latest release (V1.6&V1.7), such as cross-chain programmability, delegate upload, and sponsor-paid storage fees. With these features, developers can easily create a web3 decentralized trading platform based on the BNB Chain ecosystem with a great user experience and comprehensive functions such as storage, trading, and content permission management, thereby accelerating project development and marketing.

## Features
As an image stock, sellers can upload and list photos for sale, while buyers can search for images they like, buy, and download the original files.

### Seller
- **Upload objects (e.g. images) to BNB Greenfield**: Sellers can upload multiple images to BNB Greenfield at once under the BSC network.
- **List objects on the BNB Smart Chain**: Sellers can list their uploaded images for sale on the BSC network and begin selling download/view permissions to buyers to earn money.

### Buyer
- **Search objects**: Buyers can search for objects by name and category ID to find what they want.
- **Buy objects**: Buyers can purchase objects and obtain download/view permission.
- **Download objects**: Buyers can download/view their purchased objects.

## Environment Support

- BNB Greenfield Mainnet
- BNB Greenfield Testnet

## Technical Design
### Tech Stack
- Solidity
- Typescript
- Foundry

### Architecture Diagram
<p align="center">
    <img width="600px" src="mind-marketplace-architecture.png" alt="">
</p>

### Technical Considerations


### Upcoming Changes
- Delist objects
- List process optimization from 2 steps to 1 step

## Install

To install dependencies:

```bash
git clone --recurse-submodules https://github.com/bnb-chain/mind-marketplace-contract.git && cd mind-marketplace-contract
yarn install
forge install
```

## Deploy

1. Copy `.env.example` and setup `OP_PRIVATE_KEY` and `OWNER_PRIVATE_KEY` in `.env`.

```bash
cp .env.example .env
```

2. Deploy with hardhat.

```bash
npx hardhat run scripts/1-deploy.ts --network bsc-testnet 
```

## Documentation

| Description                                                                                                  |
| ------------------------------------------------------------------------------------------------------------ |
| [BNB greenfield official website](https://greenfield.bnbchain.org/en)                                        |
| [Guide to BNB Greenfield](https://docs.bnbchain.org/greenfield-docs/docs/guide/home)                         |
| [Discord of BNB Greenfield](https://discord.gg/bnbchain)                                                     |
| [Forum of bnbchain](https://forum.bnbchain.org/)                                                             |
| [Guide to BNB Greenfield](https://docs.bnbchain.org/greenfield-docs/docs/guide/home)                         |
