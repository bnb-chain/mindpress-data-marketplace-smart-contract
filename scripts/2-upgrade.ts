import { ProxyAdmin } from '../typechain-types';
import { toHuman } from './helper';
const { ethers } = require('hardhat');

const log = console.log;

let owner: string;

const main = async () => {
    const { chainId } = await ethers.provider.getNetwork();
    log('chainId', chainId);
    const contracts: any = require(`../deployment/${chainId}-deployment.json`);

    const [operator, ownerSigner] = await ethers.getSigners();
    owner = ownerSigner.address;
    log('operator', operator.address, 'owner', owner);

    const balance = await ethers.provider.getBalance(operator.address);
    const network = await ethers.provider.getNetwork();
    log('network', network);
    log('operator.address: ', operator.address, toHuman(balance));

    const implMarketplace = await deployContract('Marketplace');
    log('deploy Marketplace success', implMarketplace.address);

    const proxyAdmin = (await ethers.getContractAt('ProxyAdmin', contracts.ProxyAdmin)).connect(
        ownerSigner
    ) as ProxyAdmin;
    const tx = await proxyAdmin.upgrade(contracts.Marketplace, implMarketplace.address);
    await tx.wait(1);
    log('upgraded Marketplace New Impl', implMarketplace.address);
};

const deployContract = async (factoryPath: string, ...args: any) => {
    const factory = await ethers.getContractFactory(factoryPath);
    const contract = await factory.deploy(...args);
    await contract.deployTransaction.wait(1);
    return contract;
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
