import { Deployer } from '../typechain-types';
import { toHuman } from './helper';
import fs from 'fs';
const { ethers, run } = require('hardhat');

const log = console.log;

const main = async () => {
    const { chainId } = await ethers.provider.getNetwork();
    log('chainId', chainId);
    const contracts: any = require(`../deployment/${chainId}-deployment.json`);

    const [operator] = await ethers.getSigners();
    const balance = await ethers.provider.getBalance(operator.address);
    log('operator.address: ', operator.address, toHuman(balance));

    const deployer = (await ethers.getContractAt('Deployer', contracts.Deployer)) as Deployer;

    try {
        await run('verify:verify', {
            address: contracts.Deployer,
        });
    } catch (e) {
        log('verify Deployer error', e);
    }

    const proxyAdmin = await deployer.proxyAdmin();
    const implMarketplace = await deployer.implMarketplace();
    const proxyMarketplace = await deployer.proxyMarketplace();
    try {
        await run('verify:verify', {
            address: proxyAdmin,
        });
        await run('verify:verify', { address: implMarketplace });
        await run('verify:verify', {
            address: proxyMarketplace,
            constructorArguments: [implMarketplace, proxyAdmin, '0x'],
        });
        log('proxyAdmin and all impl contract verified');
    } catch (e) {
        log('verify error', e);
    }
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
