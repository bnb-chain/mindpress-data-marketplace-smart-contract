// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts/contracts/interface/IERC721NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IERC1155NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IGnfdAccessControl.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IBucketHub.sol";
import "@bnb-chain/greenfield-contracts-sdk/GroupApp.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableMapUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";
import "./interface/IGreenfieldExecutor.sol";

contract Marketplace is ReentrancyGuard, AccessControl, GroupApp {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // TODO: set greenfield system contracts on Mainnet
    // testnet env
    address public constant _CROSS_CHAIN = 0xa5B2c9194131A4E0BFaCbF9E5D6722c873159cb7;
    address public constant _GROUP_HUB = 0x50B3BF0d95a8dbA57B58C82dFDB5ff6747Cc1a9E;
    address public constant _BUCKET_HUB = 0x5BB17A87D03620b313C39C24029C94cB5714814A;
    address public constant _PERMISSION_HUB = 0x25E1eeDb5CaBf288210B132321FBB2d90b4174ad;
    address public constant _GROUP_TOKEN = 0x7fC61D6FCA8D6Ea811637bA58eaf6aB17d50c4d1;
    address public constant _MEMBER_TOKEN = 0x43bdF3d63e6318A2831FE1116cBA69afd0F05267;
    address public constant _MULTI_MESSAGE = 0x54be643072eB8cF38Ac0c57Abc72b9c0368C8699;
    address public constant _GREENFIELD_EXECUTOR = 0x3E3180883308e8B4946C9a485F8d91F8b15dC48e;

    uint256 public constant CACHE_MIN_LIST_GROUPS = 20;

    /*----------------- storage -----------------*/
    // group ID => item price
    mapping(uint256 => uint256) public prices;

    // address => unclaimed amount
    mapping(address => uint256) private _unclaimedFunds;

    address public fundWallet;

    uint256 public transferGasLimit; // 2300 for now
    uint256 public feeRate; // 10000 = 100%

    EnumerableSetUpgradeable.UintSet private listGroupIds;

    // creator => collection
    mapping(address => Collection) public collectionMap;

    // objectId => groupId
    mapping(uint256 => uint256) public objectToGroupId;

    struct Collection {
        uint256 bucketId;
        uint256[] listGroupIds;
    }

    /*----------------- event/modifier -----------------*/
    event List(address indexed owner, uint256 indexed groupId, uint256 price);
    event Delist(address indexed owner, uint256 indexed groupId);
    event Buy(address indexed buyer, uint256 indexed groupId);
    event BuyFailed(address indexed buyer, uint256 indexed groupId);
    event PriceUpdated(address indexed owner, uint256 indexed groupId, uint256 price);
    event AddedListGroup(address indexed creator, uint256 indexed groupId);

    modifier onlyGroupOwner(uint256 groupId) {
        require(msg.sender == IERC721NonTransferable(_GROUP_TOKEN).ownerOf(groupId), "MarketPlace: only group owner");
        _;
    }

    function initialize(
        address _initAdmin,
        address _fundWallet,
        uint256 _feeRate,
        uint256 _callbackGasLimit,
        uint8 _failureHandleStrategy
    ) public initializer {
        require(_initAdmin != address(0), "MarketPlace: invalid admin address");
        _grantRole(DEFAULT_ADMIN_ROLE, _initAdmin);

        transferGasLimit = 2300;
        fundWallet = _fundWallet;
        feeRate = _feeRate;

        __base_app_init_unchained(_CROSS_CHAIN, _callbackGasLimit, _failureHandleStrategy);
        __group_app_init_unchained(_GROUP_HUB);
    }

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override (GroupApp) {
        if (msg.sender == _GROUP_HUB) {
            if (resourceType == RESOURCE_GROUP) {
                _groupGreenfieldCall(status, operationType, resourceId, callbackData);
            } else {
                revert("MarketPlace: invalid resource type");
            }
        } else if (msg.sender == _PERMISSION_HUB) {
            _permissionGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert("invalid caller");
        }
    }

    function createSpace(
        BucketStorage.CreateBucketSynPackage memory createPackage,
        bytes memory _executorData
    ) external payable {
        (uint256 relayFee, uint256 ackRelayFee) = ICrossChain(_CROSS_CHAIN).getRelayFees();
        require(msg.value >= relayFee + ackRelayFee + relayFee, "relay fees not enough");
        require(msg.sender == createPackage.creator, "invalid creator");

        IBucketHub(_BUCKET_HUB).createBucket{value: msg.value - relayFee}(createPackage);

        uint8[] memory _msgTypes = new uint8[](1);
        // * 9: SetBucketFlowRateLimit
        _msgTypes[0] = 9;
        bytes[] memory _msgBytes = new bytes[](1);
        _msgBytes[0] = _executorData;

        IGreenfieldExecutor(_GREENFIELD_EXECUTOR).execute{value: relayFee}(_msgTypes, _msgBytes);
    }

    function list(uint256 groupId, uint256 price) external onlyGroupOwner(groupId) {
        // the owner need to approve the marketplace contract to update the group
        require(IGnfdAccessControl(_GROUP_HUB).hasRole(ROLE_UPDATE, msg.sender, address(this)), "Marketplace: no grant");
        require(prices[groupId] == 0, "Marketplace: already listed");
        require(price > 0, "Marketplace: invalid price");

        prices[groupId] = price;

        emit List(msg.sender, groupId, price);
    }

    function setPrice(uint256 groupId, uint256 newPrice) external onlyGroupOwner(groupId) {
        require(prices[groupId] > 0, "MarketPlace: not listed");
        require(newPrice > 0, "MarketPlace: invalid price");
        prices[groupId] = newPrice;
        emit PriceUpdated(msg.sender, groupId, newPrice);
    }

    function delist(uint256 groupId) external onlyGroupOwner(groupId) {
        require(prices[groupId] > 0, "MarketPlace: not listed");

        delete prices[groupId];

        emit Delist(msg.sender, groupId);
    }

    function buy(uint256 groupId, address refundAddress) external payable {
        uint256 price = prices[groupId];
        require(price > 0, "MarketPlace: not listed");
        require(msg.value >= prices[groupId] + _getTotalFee(), "MarketPlace: insufficient fund");

        _buy(groupId, refundAddress, msg.value - price);
    }

    function buyBatch(uint256[] calldata groupIds, address refundAddress) external payable {
        uint256 receivedValue = msg.value;
        uint256 relayFee = _getTotalFee();
        uint256 amount;
        for (uint256 i; i < groupIds.length; ++i) {
            require(prices[groupIds[i]] > 0, "MarketPlace: not listed");

            amount = prices[groupIds[i]] + relayFee;
            require(receivedValue >= amount, "MarketPlace: insufficient fund");
            receivedValue -= amount;

            _buy(groupIds[i], refundAddress, relayFee);
        }
        if (receivedValue > 0) {
            (bool success,) = payable(refundAddress).call{gas: transferGasLimit, value: receivedValue}("");
            if (!success) {
                _unclaimedFunds[refundAddress] += receivedValue;
            }
        }
    }

    function claim() external nonReentrant {
        uint256 amount = _unclaimedFunds[msg.sender];
        require(amount > 0, "MarketPlace: no unclaimed funds");
        _unclaimedFunds[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "MarketPlace: claim failed");
    }

    /*----------------- view functions -----------------*/
    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (2, "MarketPlace", "b1e2d2364271044a7d918cbfea985d131c12f0a6");
    }

    function getPrice(uint256 groupId) external view returns (uint256 price) {
        price = prices[groupId];
        require(price > 0, "MarketPlace: not listed");
    }

    function getMinRelayFee() external returns (uint256 amount) {
        amount = _getTotalFee();
    }

    function getUnclaimedAmount() external view returns (uint256 amount) {
        amount = _unclaimedFunds[msg.sender];
    }

    function getListGroupId(address lister) external view returns (uint256 id) {
        uint256 len = listGroupIds.length();
        if (len == 0) {
            return 0;
        }

        uint256 index = uint256(keccak256(abi.encodePacked(lister, block.timestamp))) % len;
        return listGroupIds.at(index);
    }

    function getAllListGroupId(address lister) external view returns (uint256[] memory) {
        return listGroupIds.values();
    }

    /*----------------- admin functions -----------------*/
    function addOperator(address newOperator) external {
        grantRole(OPERATOR_ROLE, newOperator);
    }

    function removeOperator(address operator) external {
        revokeRole(OPERATOR_ROLE, operator);
    }

    function setFundWallet(address _fundWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fundWallet = _fundWallet;
    }

    function retryPackage(uint8) external override onlyRole(OPERATOR_ROLE) {
        _retryGroupPackage();
    }

    function skipPackage(uint8) external override onlyRole(OPERATOR_ROLE) {
        _skipGroupPackage();
    }

    function setFeeRate(uint256 _feeRate) external onlyRole(OPERATOR_ROLE) {
        require(_feeRate < 10_000, "MarketPlace: invalid feeRate");
        feeRate = _feeRate;
    }

    function setCallbackGasLimit(uint256 _callbackGasLimit) external onlyRole(OPERATOR_ROLE) {
        _setCallbackGasLimit(_callbackGasLimit);
    }

    function setFailureHandleStrategy(uint8 _failureHandleStrategy) external onlyRole(OPERATOR_ROLE) {
        _setFailureHandleStrategy(_failureHandleStrategy);
    }

    function setTransferGasLimit(uint256 _transferGasLimit) external onlyRole(OPERATOR_ROLE) {
        transferGasLimit = _transferGasLimit;
    }

    /*----------------- internal functions -----------------*/
    function _buy(uint256 groupId, address refundAddress, uint256 amount) internal {
        address buyer = msg.sender;
        require(IERC1155NonTransferable(_MEMBER_TOKEN).balanceOf(buyer, groupId) == 0, "MarketPlace: already purchased");

        address _owner = IERC721NonTransferable(_GROUP_TOKEN).ownerOf(groupId);
        address[] memory members = new address[](1);
        uint64[] memory expirations = new uint64[](1);
        members[0] = buyer;
        expirations[0] = 0;
        bytes memory callbackData = abi.encode(_owner, buyer, prices[groupId]);
        UpdateGroupSynPackage memory updatePkg = UpdateGroupSynPackage({
            operator: _owner,
            id: groupId,
            opType: UpdateGroupOpType.AddMembers,
            members: members,
            extraData: "",
            memberExpiration: expirations
        });
        ExtraData memory _extraData = ExtraData({
            appAddress: address(this),
            refundAddress: refundAddress,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: callbackData
        });

        IGroupHub(_GROUP_HUB).updateGroup{value: amount}(updatePkg, callbackGasLimit, _extraData);
    }

    function _permissionGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal {
        require(operationType == TYPE_CREATE, "invalid permission operationType");
        require(listGroupIds.length() > CACHE_MIN_LIST_GROUPS, "cache list groups not enough");

        (address lister, uint256 groupId, uint256 bucketId, uint256 objectId, uint256 objectPrice) = abi.decode(callbackData, (address, uint256, uint256, uint256, uint256));
        require(resourceId == objectId, "resource mismatch");

        require(listGroupIds.contains(groupId), "groupId not for list");
        require(prices[groupId] == 0, "groupId already listed");
        require(objectPrice > 0, "zero price");
        require(collectionMap[lister].bucketId == bucketId, "bucket mismatch");

        listGroupIds.remove(groupId);
        prices[groupId] = objectPrice;
        objectToGroupId[objectId] = groupId;
        collectionMap[lister].listGroupIds.push(groupId);
    }

    function _groupGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal override {
        if (operationType == TYPE_UPDATE) {
            _updateGroupCallback(status, resourceId, callbackData);
        } else if (operationType == TYPE_CREATE) {
            _createGroupCallback(status, resourceId, callbackData);
        } else {
            revert("MarketPlace: invalid operation type");
        }
    }

    function _updateGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal override {
        (address owner, address buyer, uint256 price) = abi.decode(_callbackData, (address, address, uint256));

        if (_status == STATUS_SUCCESS) {
            uint256 feeRateAmount = (price * feeRate) / 10_000;
            (bool success,) = fundWallet.call{value: feeRateAmount}("");
            require(success, "MarketPlace: transfer fee failed");
            (success,) = owner.call{gas: transferGasLimit, value: price - feeRateAmount}("");
            if (!success) {
                _unclaimedFunds[owner] += price - feeRateAmount;
            }
            emit Buy(buyer, _tokenId);
        } else {
            (bool success,) = buyer.call{gas: transferGasLimit, value: price}("");
            if (!success) {
                _unclaimedFunds[buyer] += price;
            }
            emit BuyFailed(buyer, _tokenId);
        }
    }

    function _createGroupCallback(uint32 _status, uint256 _tokenId, bytes memory _callbackData) internal override {
        (address creator) = abi.decode(_callbackData, (address));

        if (_status == STATUS_SUCCESS) {
            if (creator != address(this)) {

            } else {
                require(IERC721NonTransferable(_GROUP_TOKEN).ownerOf(groupId) == address(this), "");

            }
            listGroupIds.add(_tokenId);
            emit AddedListGroup(creator, _tokenId);
        } else {

            (bool success,) = buyer.call{gas: transferGasLimit, value: price}("");
            if (!success) {
                _unclaimedFunds[buyer] += price;
            }
            emit BuyFailed(buyer, _tokenId);

        }
    }

    // placeHolder reserved for future usage
    uint256[50] private __reservedSlots;
}
