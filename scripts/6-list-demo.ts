import { keccak256 } from 'ethers/lib/utils';
import {
    AccessControl,
    BucketHub,
    GroupHub,
    IBucketHub,
    ICrossChain,
    IERC721, ITrustedForwarder,
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
    const ERC2771_FORWARDER = await market.ERC2771_FORWARDER();

    const forwarder = (await ethers.getContractAt('ITrustedForwarder', ERC2771_FORWARDER)).connect(
        operator
    ) as ITrustedForwarder;


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

    const [relayFee, ackRelayFee] = await crossChain.callStatic.getRelayFees();
    const totalRelayerFee = relayFee.add(ackRelayFee).add(relayFee);
    // TODO
    const callbackFee = BigNumber.from(0)
    const calls: any = [
        {
            target: contracts.Marketplace,
            allowFailure: false,
            value: totalRelayerFee.add(callbackFee),
            data: market.interface.encodeFunctionData(
                "list",
                ['groupName', 1, "description", 1, "picture-url", 1]
            )
        },
        {
            target: _PERMISSION_HUB,
            allowFailure: false,
            value: totalRelayerFee,
            data: permissionHub.interface.encodeFunctionData(
                'createPolicy(bytes)',
                ['0x']
            )
        }
    ]

    let totalValue = BigNumber.from(0)
    for (let i = 0; i < calls.length; i++) {
        totalValue = totalValue.add(calls[i].value)
    }

    const tx = await forwarder.aggregate3Value(calls, { value: totalValue });
    await tx.wait(1)
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
