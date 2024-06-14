// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@bnb-chain/greenfield-contracts/contracts/interface/IERC721NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IERC1155NonTransferable.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IGnfdAccessControl.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IBucketHub.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IMultiMessage.sol";
import "@bnb-chain/greenfield-contracts-sdk/GroupApp.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableMapUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";
import "./interface/IGreenfieldExecutor.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

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

    /**
     * @dev The eip-2771 defines a contract-level protocol for Recipient contracts to accept
     * meta-transactions through trusted Forwarder contracts. No protocol changes are made.
     * Recipient contracts are sent the effective msg.sender (referred to as _msgSender())
     * and msg.data (referred to as _msgData()) by appending additional calldata.
     * eip-2771 doc: https://eips.ethereum.org/EIPS/eip-2771
     * openzeppelin eip-2771 contract: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/metatx/ERC2771Forwarder.sol
     * The ERC2771_FORWARDER contract deployed from: https://github.com/bnb-chain/ERC2771Forwarder.git
     */
    address public constant ERC2771_FORWARDER = 0xdb7d0bd38D223048B1cFf39700E4C5238e346f7F;
    uint256 private constant CONTEXT_SUFFIX_LENGTH = 20;
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
    mapping(uint256 => address) public groupToLister;
    uint256 public totalGroups;
    mapping(string => uint256) public groupNameToId;

    // groupId => ListItem info
    mapping(uint256 => ListItem) public listItems;

    // groupId => buyer => bought price
    mapping(uint256 => mapping(address => uint256)) public buyPrice;
    mapping(uint256 => string) public listUrl;

    // categoryId => listed group ids
    mapping(uint256 => uint256[]) public categoryListedIds;

    // groupId => objectId
    mapping(uint256 => uint256) public objectIdMap;

    struct Collection {
        uint256 bucketId;
        uint256[] listGroupIds;
    }

    struct ListItem {
        string groupName;
        string description;
        uint256 categoryId;
        address creator;
    }

    /*----------------- event/modifier -----------------*/
    event List(address indexed owner, uint256 indexed groupId, uint256 price);
    event Delist(address indexed owner, uint256 indexed groupId);
    event Buy(address indexed buyer, uint256 indexed groupId);
    event BuyFailed(address indexed buyer, uint256 indexed groupId);
    event PriceUpdated(address indexed owner, uint256 indexed groupId, uint256 price);
    event AddedListGroup(address indexed creator, uint256 indexed groupId);

    modifier onlyGroupOwner(uint256 groupId) {
        require(
            _erc2771Sender() == IERC721NonTransferable(_GROUP_TOKEN).ownerOf(groupId), "MarketPlace: only group owner"
        );
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
        IGnfdAccessControl(_GROUP_HUB).grantRole(ROLE_CREATE, _initAdmin, block.timestamp + 10 * 365 days);

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
        if (msg.sender == _GROUP_HUB) {
            if (resourceType == RESOURCE_GROUP) {
                _groupGreenfieldCall(status, operationType, resourceId, callbackData);
            } else {
                revert("MarketPlace: invalid resource type");
            }
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
        require(_erc2771Sender() == createPackage.creator, "invalid creator");

        IBucketHub(_BUCKET_HUB).createBucket{value: msg.value - relayFee}(createPackage);

        uint8[] memory _msgTypes = new uint8[](1);
        // * 9: SetBucketFlowRateLimit
        _msgTypes[0] = 9;
        bytes[] memory _msgBytes = new bytes[](1);
        _msgBytes[0] = _executorData;

        IGreenfieldExecutor(_GREENFIELD_EXECUTOR).execute{value: relayFee}(_msgTypes, _msgBytes);
    }

    function list(
        string calldata groupName,
        uint256 price,
        string calldata description,
        uint256 categoryId,
        string calldata url,
        uint256 objectId
    ) external payable {
        require(price > 0, "invalid price");
        address _sender = _erc2771Sender();

        ExtraData memory extraData = ExtraData({
            appAddress: address(this),
            refundAddress: _sender,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: abi.encode(_sender, groupName, price, description, categoryId, url, objectId)
        });
        IGroupHub(_GROUP_HUB).createGroup{value: msg.value}(address(this), groupName, callbackGasLimit, extraData);
    }

    function getGroupId(string memory groupName) external view returns (uint256 groupId) {
        return groupNameToId[groupName];
    }

    function delist(uint256 groupId) external {
        require(prices[groupId] > 0, "MarketPlace: not listed");

        address _sender = _erc2771Sender();
        require(listItems[groupId].creator == _sender, "MarketPlace: not creator");

        delete prices[groupId];

        uint256 categoryId = listItems[groupId].categoryId;
        uint256[] storage listedIds = categoryListedIds[categoryId];
        for (uint256 i = 0; i < listedIds.length; i++) {
            if (listedIds[i] == groupId) {
                listedIds[i] = listedIds[listedIds.length - 1];
                listedIds.pop();
                break;
            }
        }
        emit Delist(_sender, groupId);
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
        return (3, "MarketPlace", "support erc2771");
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

    function getListItem(
        uint256 groupId,
        address buyer
    )
        external
        view
        returns (
            bool isBought,
            string memory groupName,
            string memory description,
            uint256 categoryId,
            address creator,
            uint256 price
        )
    {
        isBought = buyPrice[groupId][buyer] > 0;
        groupName = listItems[groupId].groupName;
        description = listItems[groupId].description;
        categoryId = listItems[groupId].categoryId;
        creator = listItems[groupId].creator;
        price = prices[groupId];
    }

    function getListItems(uint256[] calldata groupIds)
        external
        view
        returns (
            string[] memory groupNames,
            string[] memory descriptions,
            uint256[] memory categoryIds,
            address[] memory creators,
            uint256[] memory priceList,
            string[] memory urls,
            uint256[] memory objectIds
        )
    {
        uint256 cnt = groupIds.length;
        groupNames = new string[](cnt);
        descriptions = new string[](cnt);
        categoryIds = new uint256[](cnt);
        creators = new address[](cnt);
        priceList = new uint256[](cnt);
        urls = new string[](cnt);
        objectIds = new uint256[](cnt);

        uint256 groupId;
        for (uint256 i = 0; i < cnt; i++) {
            groupId = groupIds[i];

            groupNames[i] = listItems[groupId].groupName;
            descriptions[i] = listItems[groupId].description;
            categoryIds[i] = listItems[groupId].categoryId;
            creators[i] = listItems[groupId].creator;
            priceList[i] = prices[groupId];
            urls[i] = listUrl[groupId];
            objectIds[i] = objectIdMap[groupId];
        }
    }

    function getListedGroupIds(uint256 categoryId) external view returns (uint256[] memory) {
        return categoryListedIds[categoryId];
    }

    function isTrustedForwarder(address forwarder) public pure returns (bool) {
        return forwarder == ERC2771_FORWARDER;
    }

    function getErc2771Sender() external view returns (address) {
        return _erc2771Sender();
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
        address buyer = _erc2771Sender();
        require(IERC1155NonTransferable(_MEMBER_TOKEN).balanceOf(buyer, groupId) == 0, "MarketPlace: already purchased");

        address _owner = listItems[groupId].creator;
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

            buyPrice[_tokenId][buyer] = price;
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
        (
            address lister,
            string memory groupName,
            uint256 price,
            string memory description,
            uint256 categoryId,
            string memory url,
            uint256 objectId
        ) = abi.decode(_callbackData, (address, string, uint256, string, uint256, string, uint256));

        if (_status == STATUS_SUCCESS) {
            require(IERC721NonTransferable(_GROUP_TOKEN).ownerOf(_tokenId) == address(this), "invalid group owner");

            listItems[_tokenId].creator = lister;
            listItems[_tokenId].groupName = groupName;
            listItems[_tokenId].description = description;
            listItems[_tokenId].categoryId = categoryId;

            prices[_tokenId] = price;
            listUrl[_tokenId] = url;

            groupNameToId[groupName] = _tokenId;
            categoryListedIds[categoryId].push(_tokenId);

            objectIdMap[_tokenId] = objectId;
            emit List(lister, _tokenId, price);
        }
    }

    /**
     * @dev Override for `msg.sender`. Defaults to the original `msg.sender` whenever
     * a call is not performed by the trusted forwarder or the calldata length is less than
     * 20 bytes (an address length).
     */
    function _erc2771Sender() internal view returns (address) {
        uint256 calldataLength = msg.data.length;
        uint256 contextSuffixLength = CONTEXT_SUFFIX_LENGTH;
        if (isTrustedForwarder(msg.sender) && calldataLength >= contextSuffixLength) {
            return address(bytes20(msg.data[calldataLength - contextSuffixLength:]));
        } else {
            return msg.sender;
        }
    }

    // placeHolder reserved for future usage
    uint256[50] private __reservedSlots;
}
