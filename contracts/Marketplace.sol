// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts/contracts/interface/IERC721NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IERC1155NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IGnfdAccessControl.sol";
import "@bnb-chain/greenfield-contracts-sdk/GroupApp.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableMapUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";

contract Marketplace is ReentrancyGuard, AccessControl, GroupApp {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /*----------------- constants -----------------*/
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // greenfield system contracts
    address public constant _CROSS_CHAIN = 0x77e719b714be09F70D484AB81F70D02B0E182f7d;
    address public constant _GROUP_HUB = 0xDd9af4573D64324125fCa5Ce13407be79331B7F7;
    address public constant _GROUP_TOKEN = 0x943FAC6CEBE6e45CE59bA911E5B6447c1a991450;
    address public constant _MEMBER_TOKEN = 0xAb73f243Be4d0fC5644c822351eC77e85DC2B5Ea;

    /*----------------- storage -----------------*/
    // group ID => item price
    mapping(uint256 => uint256) public prices;

    // address => unclaimed amount
    mapping(address => uint256) private _unclaimedFunds;

    address public fundWallet;

    uint256 public transferGasLimit; // 2300 for now
    uint256 public feeRate; // 10000 = 100%

    /*----------------- event/modifier -----------------*/
    event List(address indexed owner, uint256 indexed groupId, uint256 price);
    event Delist(address indexed owner, uint256 indexed groupId);
    event Buy(address indexed buyer, uint256 indexed groupId);
    event BuyFailed(address indexed buyer, uint256 indexed groupId);
    event PriceUpdated(address indexed owner, uint256 indexed groupId, uint256 price);

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
    ) external override(GroupApp) {
        require(msg.sender == _GROUP_HUB, "MarketPlace: invalid caller");

        if (resourceType == RESOURCE_GROUP) {
            _groupGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert("MarketPlace: invalid resource type");
        }
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

    function _groupGreenfieldCall(
        uint32 status,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) internal override {
        if (operationType == TYPE_UPDATE) {
            _updateGroupCallback(status, resourceId, callbackData);
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

    // placeHolder reserved for future usage
    uint256[50] private __reservedSlots;
}
