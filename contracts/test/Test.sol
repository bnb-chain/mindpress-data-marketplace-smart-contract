// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts/contracts/middle-layer/resource-mirror/BucketHub.sol";
import "@bnb-chain/greenfield-contracts/contracts/middle-layer/resource-mirror/GroupHub.sol";
import "@bnb-chain/greenfield-contracts/contracts/middle-layer/resource-mirror/PermissionHub.sol";
import "@bnb-chain/greenfield-contracts/contracts/middle-layer/resource-mirror/MultiMessage.sol";
import "@bnb-chain/greenfield-contracts/contracts/middle-layer/GreenfieldExecutor.sol";

contract Test1 is BucketHub {}

contract Test2 is MultiMessage {}

contract Test3 is GreenfieldExecutor {}

contract Test4 is GroupHub {}

contract Test5 is PermissionHub {}
