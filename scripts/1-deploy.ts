import { Deployer } from '../typechain-types';
import { toHuman } from './helper';
import fs from 'fs';

const { execSync } = require('child_process');
const { ethers } = require('hardhat');

const log = console.log;
const unit = ethers.constants.WeiPerEther;

// deploy config
const callbackGasLimit = 1_000_000; // TODO: TBD
const failureHandleStrategy = 0; // BlockOnFail
const tax = 100; // 1%
let owner: string;

const main = async () => {
    const commitId = await getCommitId();
    const [operator, ownerSigner] = await ethers.getSigners();
    owner = ownerSigner.address;
    log('operator', operator.address, 'owner', owner);

    const balance = await ethers.provider.getBalance(operator.address);
    const network = await ethers.provider.getNetwork();
    log('network', network);
    log('operator.address: ', operator.address, toHuman(balance));

    const deployer = (await deployContract('Deployer')) as Deployer;
    log('Deployer deployed', deployer.address);

    const proxyAdmin = await deployer.proxyAdmin();
    const proxyMarketplace = await deployer.proxyMarketplace();

    const implMarketplace = await deployContract('Marketplace');
    log('deploy Marketplace success', implMarketplace.address);

    let tx = await deployer.deploy(
        implMarketplace.address,
        owner,
        owner,
        tax,
        callbackGasLimit,
        failureHandleStrategy
    );
    await tx.wait(1);
    log('deploy success');

    const blockNumber = await ethers.provider.getBlockNumber();
    const deployment: any = {
        DeployCommitId: commitId,
        BlockNumber: blockNumber,

        Deployer: deployer.address,

        ProxyAdmin: proxyAdmin,
        Marketplace: proxyMarketplace,
        implMarketplace: implMarketplace.address,
    };
    log('all contracts', JSON.stringify(deployment, null, 2));

    const deploymentDir = __dirname + `/../deployment`;
    if (!fs.existsSync(deploymentDir)) {
        fs.mkdirSync(deploymentDir, { recursive: true });
    }
    fs.writeFileSync(
        `${deploymentDir}/${network.chainId}-deployment.json`,
        JSON.stringify(deployment, null, 2)
    );
};

const deployContract = async (factoryPath: string, ...args: any) => {
    const factory = await ethers.getContractFactory(factoryPath);
    const contract = await factory.deploy(...args);
    await contract.deployTransaction.wait(1);
    return contract;
};

const getCommitId = async (): Promise<string> => {
    try {
        const result = execSync('git rev-parse HEAD');
        log('getCommitId', result.toString().trim());
        return result.toString().trim();
    } catch (e) {
        console.error('getCommitId error', e);
        return '';
    }
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
