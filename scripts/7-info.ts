import { keccak256 } from 'ethers/lib/utils';
import {
    AccessControl,
    BucketHub,
    GroupHub,
    IBucketHub,
    ICrossChain,
    IERC721,
    Marketplace,
    MultiMessage,
    PermissionHub,
    ProxyAdmin,
} from '../typechain-types';
import { toHuman } from './helper';
import { address } from 'hardhat/internal/core/config/config-validation';
import type { PromiseOrValue } from '../typechain-types/common';
import { BigNumber, BigNumberish, BytesLike } from 'ethers';
const { ethers } = require('hardhat');

const log = console.log;

let owner: string;

const main = async () => {
    const { chainId } = await ethers.provider.getNetwork();
    log('chainId', chainId);
    const contracts: any = require(`../deployment/${chainId}-deployment.json`);

    const [op, ownerSigner, operator] = await ethers.getSigners();
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
    const _PERMISSION_HUB = await market._PERMISSION_HUB();
    const _MULTI_MESSAGE = await market._MULTI_MESSAGE();
    const _GREENFIELD_EXECUTOR = await market._GREENFIELD_EXECUTOR();
    const _GROUP_TOKEN = await market._GROUP_TOKEN();

    log('_MULTI_MESSAGE', _MULTI_MESSAGE);
    const multiMessage = (await ethers.getContractAt('MultiMessage', _MULTI_MESSAGE)).connect(
        operator
    ) as MultiMessage;

    log('_CROSS_CHAIN', _CROSS_CHAIN);
    const crossChain = (await ethers.getContractAt('ICrossChain', _CROSS_CHAIN)).connect(
        operator
    ) as ICrossChain;

    const groupHub = (await ethers.getContractAt('GroupHub', _GROUP_HUB)).connect(
        operator
    ) as GroupHub;

    const permissionHub = (await ethers.getContractAt('PermissionHub', _PERMISSION_HUB)).connect(
        operator
    ) as PermissionHub;

    const groupToken = (await ethers.getContractAt('IERC721', _GROUP_TOKEN)).connect(
        operator
    ) as IERC721;

    const id = await market.getGroupId(
        'mindt0125_o_mindpress-0x1c893441ab6c1a75e01887087ea508be8e07aaae_1715766494670.thumb.1 2.png'
    );
    log('groupId', id);
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
