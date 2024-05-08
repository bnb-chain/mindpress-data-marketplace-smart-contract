import { keccak256 } from 'ethers/lib/utils';
import {
    AccessControl,
    BucketHub,
    IBucketHub,
    ICrossChain,
    Marketplace,
    ProxyAdmin,
} from '../typechain-types';
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

    const market = (await ethers.getContractAt('Marketplace', contracts.Marketplace)).connect(
        operator
    ) as Marketplace;

    const _CROSS_CHAIN = await market._CROSS_CHAIN();
    const _GROUP_HUB = await market._GROUP_HUB();
    const _BUCKET_HUB = await market._BUCKET_HUB();
    const _MULTI_MESSAGE = await market._MULTI_MESSAGE();
    const _GREENFIELD_EXECUTOR = await market._GREENFIELD_EXECUTOR();

    log('_CROSS_CHAIN', _CROSS_CHAIN);
    const crossChain = (await ethers.getContractAt('ICrossChain', _CROSS_CHAIN)).connect(
        operator
    ) as ICrossChain;

    log('_BUCKET_HUB', _BUCKET_HUB);
    const bucketHub = (await ethers.getContractAt('BucketHub', _BUCKET_HUB)).connect(
        operator
    ) as BucketHub;

    // 1. grant role for Marketplace
    const ROLE_CREATE = ethers.utils.solidityKeccak256(['string'], ['ROLE_CREATE']);
    log('ROLE_CREATE', ROLE_CREATE);

    const hasRole = await bucketHub.hasRole(ROLE_CREATE, operator.address, market.address);
    log('hasRole', hasRole);

    if (!hasRole) {
        const expireTime = Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60;
        const tx = await bucketHub.grantRole(ROLE_CREATE, market.address, expireTime);
        await tx.wait(1);
        log('role granted');
    }

    // 2. create space
    const bucketName = 'mindpress-test';
    const bucketPkg = {
        creator: operator.address,
        name: bucketName,
        visibility: 2, // private
        paymentAddress: market.address,
        primarySpAddress: ethers.constants.AddressZero,
        primarySpApprovalExpiredHeight: 0,
        primarySpSignature: '0x', // TODO if the owner of the bucket is a smart contract, we are not able to get the primarySpSignature
        chargedReadQuota: 0,
        extraData: '0x', // abi.encode of ExtraData
    };

    // TODO
    const dataSetBucketFlowRateLimit = '';

    const [relayFee, ackRelayFee] = await crossChain.callStatic.getRelayFees();
    const value = relayFee.add(ackRelayFee).add(relayFee);
    const tx = await market.createSpace(bucketPkg, dataSetBucketFlowRateLimit, { value });
    await tx.wait(1);
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
