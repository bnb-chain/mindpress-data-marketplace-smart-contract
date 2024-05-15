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

    // 2. list object
    // check group nft approved
    const isApproved = await groupToken.isApprovedForAll(operator.address, contracts.Marketplace);
    if (!isApproved) {
        const tx = await groupToken.setApprovalForAll(contracts.Marketplace, true);
        await tx.wait(1);
    }

    // 2-1. create group
    // 2-2. create policy => bind group to the object id
    const [relayFee, ackRelayFee] = await crossChain.callStatic.getRelayFees();
    const totalRelayerFee = relayFee.add(ackRelayFee).add(relayFee);
    const callbackGasPrice = await crossChain.callStatic.callbackGasPrice();

    const targets = [_GROUP_HUB, _PERMISSION_HUB];

    // TODO
    // get objectId here after upload object on greenfield
    const objectId = 123;
    const bucketId = 456;
    const objectPrice = ethers.utils.parseEther('0.123');
    const groupId = await market.getListGroupId(operator.address)

    const groupName = `list-object-group-${objectId}`;
    const callbackGasLimit = BigNumber.from(500000);
    const callbackFee = callbackGasPrice.mul(callbackGasLimit);
    const callbackDataCreateGroup = ethers.utils.solidityPack(
        ['address', 'uint256', 'uint256', 'uint256', 'uint256'],
        [
            operator.address,
            groupId,
            bucketId,
            objectId,
            objectPrice,
        ]
    );
    const createGroupData = groupHub.interface.encodeFunctionData(
        'prepareCreateGroup(address,address,string,uint256,(address,address,uint8,bytes))',
        [
            operator.address,
            operator.address,
            groupName,
            callbackGasLimit,
            {
                appAddress: market.address,
                refundAddress: operator.address,
                failureHandleStrategy: 2, // SkipOnFail
                callbackData: callbackDataCreateGroup,
            },
        ]
    );

    // TODO
    const policyDataToBindGroupToObject = '0x';
    const callbackDataCreatePolicy = ethers.utils.solidityPack(
        ['address', 'uint256', 'uint256', 'uint256', 'uint256'],
        [
            operator.address,
            groupId,
            bucketId,
            objectId,
            objectPrice,
        ]
    );
    const createPolicyData = permissionHub.interface.encodeFunctionData(
        'prepareCreatePolicy(address,bytes,(address,address,uint8,bytes))',
        [
            operator.address,
            policyDataToBindGroupToObject,
            {
                appAddress: market.address,
                refundAddress: operator.address,
                failureHandleStrategy: 2, // SkipOnFail
                callbackData: callbackDataCreatePolicy,
            },
        ]
    );
    const data = [createGroupData, createPolicyData];

    const values = [totalRelayerFee.add(callbackFee), totalRelayerFee.add(callbackFee)];
    const totalValue = values.reduce((a, b) => a.add(b));

    log(targets, data, values);
    const tx = await multiMessage.sendMessages(targets, data, values, { value: totalValue });
    await tx.wait(1);
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
