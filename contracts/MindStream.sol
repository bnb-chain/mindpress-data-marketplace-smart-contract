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

contract MindStream is ReentrancyGuard, AccessControl, GroupApp {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /*----------------- constants -----------------*/
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // greenfield system contracts
    address public constant _CROSS_CHAIN = 0x5A12cf39eA1d06D2F2B724356eCc7648276054D3;
    address public constant _GROUP_HUB = 0x55fbcA62366eD96B99ceEc3f19f7413489FB62D2;
    address public constant _GROUP_TOKEN = 0x4A5Db47C7aBe10611144B2F0E446cC1c1796BE6c;
    address public constant _MEMBER_TOKEN = 0x038E38a9Ad634D88133535c28a576FAb43750f09;

    /*----------------- storage -----------------*/
    struct Profile {
        string name;
        string avatar; // image url
        string bio;
        uint256 pubCount;
        uint256 subscribeID;
        uint256[3] prices; // price for 1 month, 3 month and 1 year
        uint256 salesVolume;
        uint256 salesRevenue;
        uint256 createTime;
    }

    enum TypesOfSubscriptions {
        OneMonth,
        ThreeMonths,
        OneYear
    }

    // all users that have created a profile, ordered by listed time
    EnumerableSetUpgradeable.AddressSet private _users;
    // author address => Profile
    mapping(address => Profile) public profileByAddress;

    // sales volume ranking list, ordered by sales volume(desc)
    uint256[] private _salesVolumeRanking;
    // author address corresponding to the sales volume ranking list, ordered by sales volume(desc)
    address[] private _salesVolumeRankingAddress;

    // sales revenue ranking list, ordered by sales revenue(desc)
    uint256[] private _salesRevenueRanking;
    // author address corresponding to the sales revenue ranking list, ordered by sales revenue(desc)
    address[] private _salesRevenueRankingAddress;

    // address => unclaimed amount
    mapping(address => uint256) private _unclaimedFunds;

    address public fundWallet;

    uint256 public transferGasLimit; // 2300 for now
    uint256 public feeRate; // 10000 = 100%

    /*----------------- event/modifier -----------------*/
    event ProfileCreated(address indexed author);
    event Subscribe(address indexed subscriber, address indexed author);
    event SubscribeFailed(address indexed subscriber, address indexed author);
    event Post(address indexed author, uint256 indexed visibility, string url);

    modifier onlyOwner(uint256 _groupId) {
        require(msg.sender == IERC721NonTransferable(_GROUP_TOKEN).ownerOf(_groupId), "MindStream: only owner");
        _;
    }

    function initialize(
        address _initAdmin,
        address _fundWallet,
        uint256 _feeRate,
        uint256 _callbackGasLimit,
        uint8 _failureHandleStrategy
    ) public initializer {
        require(_initAdmin != address(0), "MindStream: invalid admin address");
        _grantRole(DEFAULT_ADMIN_ROLE, _initAdmin);

        transferGasLimit = 2300;
        fundWallet = _fundWallet;
        feeRate = _feeRate;

        __base_app_init_unchained(_CROSS_CHAIN, _callbackGasLimit, _failureHandleStrategy);
        __group_app_init_unchained(_GROUP_HUB);

        // init sales ranking
        _salesVolumeRanking = new uint256[](10);
        _salesVolumeRankingAddress = new address[](10);
        _salesRevenueRanking = new uint256[](10);
        _salesVolumeRankingAddress = new address[](10);
    }

    /*----------------- external functions -----------------*/
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes calldata callbackData
    ) external override(GroupApp) {
        require(msg.sender == _GROUP_HUB, "MindStream: invalid caller");

        if (resourceType == RESOURCE_GROUP) {
            _groupGreenfieldCall(status, operationType, resourceId, callbackData);
        } else {
            revert("MindStream: invalid resource type");
        }
    }

    function createProfile(string calldata _name, string calldata _avatar, string calldata _bio) external {
        Profile storage _profile = profileByAddress[msg.sender];
        require(bytes(_profile.name).length == 0, "MindStream: profile already created");
        require(bytes(_name).length > 0, "MindStream: invalid name");

        _profile.name = _name;
        _profile.avatar = _avatar;
        _profile.bio = _bio;
        _profile.createTime = block.timestamp;

        _users.add(msg.sender);

        emit ProfileCreated(msg.sender);
    }

    function editProfile(string calldata _name, string calldata _avatar, string calldata _bio) external {
        Profile storage _profile = profileByAddress[msg.sender];
        require(bytes(_profile.name).length > 0, "MindStream: profile not created");

        if (bytes(_name).length > 0) {
            _profile.name = _name;
        }
        if (bytes(_avatar).length > 0) {
            _profile.avatar = _avatar;
        }
        if (bytes(_bio).length > 0) {
            _profile.bio = _bio;
        }
    }

    function openUpSubscribeChannel(uint256 _groupId, uint256[3] calldata _prices) external onlyOwner(_groupId) {
        for (uint256 i; i < _prices.length; ++i) {
            require(_prices[i] > 0, "MindStream: invalid price");
        }

        Profile storage _profile = profileByAddress[msg.sender];
        require(_profile.subscribeID == 0, "MindStream: already opened");

        _profile.subscribeID = _groupId;
        _profile.prices = _prices;
    }

    function setPrice(uint256[3] calldata _prices) external {
        Profile storage _profile = profileByAddress[msg.sender];
        require(bytes(_profile.name).length > 0, "MindStream: profile not created");
        require(_profile.subscribeID > 0, "MindStream: subscribe channel not opened");

        for (uint256 i; i < _prices.length; ++i) {
            // 0 means no change
            if (_prices[i] > 0) {
                _profile.prices = _prices;
            }
        }
    }

    function subscribe(address _author, TypesOfSubscriptions _type) external payable {
        Profile memory _profile = profileByAddress[_author];
        uint256 _groupId = _profile.subscribeID;
        uint256 _price = _profile.prices[uint256(_type)];
        require(_groupId > 0 && _price > 0, "MindStream: not subscribable");
        require(msg.value >= _price + _getTotalFee(), "MindStream: insufficient fund");

        address buyer = msg.sender;
        require(
            IERC1155NonTransferable(_MEMBER_TOKEN).balanceOf(buyer, _groupId) == 0, "MindStream: already subscribed"
        );

        address[] memory members = new address[](1);
        members[0] = buyer;
        bytes memory callbackData = abi.encode(_author, buyer, _price);
        UpdateGroupSynPackage memory updatePkg = UpdateGroupSynPackage({
            operator: _author,
            id: _groupId,
            opType: UpdateGroupOpType.AddMembers,
            members: members,
            extraData: ""
        });
        ExtraData memory _extraData = ExtraData({
            appAddress: address(this),
            refundAddress: buyer,
            failureHandleStrategy: failureHandleStrategy,
            callbackData: callbackData
        });

        IGroupHub(_GROUP_HUB).updateGroup{value: msg.value - _price}(updatePkg, callbackGasLimit, _extraData);
    }

    function claim() external nonReentrant {
        uint256 amount = _unclaimedFunds[msg.sender];
        require(amount > 0, "MindStream: no unclaimed funds");
        _unclaimedFunds[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "MindStream: claim failed");
    }

    /*----------------- view functions -----------------*/
    function versionInfo()
        external
        pure
        override
        returns (uint256 version, string memory name, string memory description)
    {
        return (1, "MindStream", "first version");
    }

    function getMinRelayFee() external returns (uint256 amount) {
        amount = _getTotalFee();
    }

    function getUnclaimedAmount() external view returns (uint256 amount) {
        amount = _unclaimedFunds[msg.sender];
    }

    function getUsersProfile(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory _addrs, Profile[] memory _profiles, uint256 _totalLength) {
        _totalLength = _users.length();
        if (offset * limit >= _totalLength) {
            return (_addrs, _profiles, _totalLength);
        }

        uint256 count = _totalLength - offset * limit;
        if (count > limit) {
            count = limit;
        }
        _addrs = new address[](count);
        _profiles = new Profile[](count);
        for (uint256 i; i < count; ++i) {
            _addrs[i] = _users.at(_totalLength - offset * limit - i - 1); // reverse order
            _profiles[i] = profileByAddress[_addrs[i]];
        }
    }

    function getSalesVolumeRanking() external view returns (address[] memory _addrs, uint256[] memory _volumes) {
        _addrs = _salesVolumeRankingAddress;
        _volumes = _salesVolumeRanking;
    }

    function getSalesRevenueRanking() external view returns (address[] memory _addrs, uint256[] memory _revenues) {
        _addrs = _salesVolumeRankingAddress;
        _revenues = _salesRevenueRanking;
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
        require(_feeRate < 10_000, "MindStream: invalid feeRate");
        feeRate = _feeRate;
    }

    function setCallbackGasLimit(uint256 _callbackGasLimit) external onlyRole(OPERATOR_ROLE) {
        _setCallbackGasLimit(_callbackGasLimit);
    }

    function setFailureHandleStrategy(uint8 _failureHandleStrategy) external onlyRole(OPERATOR_ROLE) {
        _setFailureHandleStrategy(_failureHandleStrategy);
    }

    /*----------------- internal functions -----------------*/
    function _updateSales(address _author, uint256 _price) internal {
        Profile storage _profile = profileByAddress[_author];
        // 1. update sales volume
        _profile.salesVolume += 1;

        uint256 _volume = _profile.salesVolume;
        for (uint256 i; i < _salesVolumeRanking.length; ++i) {
            if (_volume > _salesVolumeRanking[i]) {
                uint256 endIdx = _salesVolumeRanking.length - 1;
                for (uint256 j = i; j < _salesVolumeRanking.length; ++j) {
                    if (_salesVolumeRankingAddress[j] == _author) {
                        endIdx = j;
                        break;
                    }
                }
                for (uint256 k = endIdx; k > i; --k) {
                    _salesVolumeRanking[k] = _salesVolumeRanking[k - 1];
                    _salesVolumeRankingAddress[k] = _salesVolumeRankingAddress[k - 1];
                }
                _salesVolumeRanking[i] = _volume;
                _salesVolumeRankingAddress[i] = _author;
                break;
            }
        }

        // 2. update sales revenue
        _profile.salesRevenue += _price;

        uint256 _revenue = _profile.salesRevenue;
        for (uint256 i; i < _salesRevenueRanking.length; ++i) {
            if (_revenue > _salesRevenueRanking[i]) {
                uint256 endIdx = _salesRevenueRanking.length - 1;
                for (uint256 j = i; j < _salesRevenueRanking.length; ++j) {
                    if (_salesVolumeRankingAddress[j] == _author) {
                        endIdx = j;
                        break;
                    }
                }
                for (uint256 k = endIdx; k > i; --k) {
                    _salesRevenueRanking[k] = _salesRevenueRanking[k - 1];
                    _salesVolumeRankingAddress[k] = _salesVolumeRankingAddress[k - 1];
                }
                _salesRevenueRanking[i] = _revenue;
                _salesVolumeRankingAddress[i] = _author;
                break;
            }
        }
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
            revert("MindStream: invalid operation type");
        }
    }

    function _updateGroupCallback(uint32 _status, uint256, bytes memory _callbackData) internal override {
        (address _author, address buyer, uint256 _price) = abi.decode(_callbackData, (address, address, uint256));

        if (_status == STATUS_SUCCESS) {
            uint256 feeRateAmount = (_price * feeRate) / 10_000;
            payable(fundWallet).transfer(feeRateAmount);
            (bool success,) = payable(_author).call{gas: transferGasLimit, value: _price - feeRateAmount}("");
            if (!success) {
                _unclaimedFunds[_author] += _price - feeRateAmount;
            }
            _updateSales(_author, _price);
            emit Subscribe(buyer, _author);
        } else {
            (bool success,) = payable(buyer).call{gas: transferGasLimit, value: _price}("");
            if (!success) {
                _unclaimedFunds[buyer] += _price;
            }
            emit SubscribeFailed(buyer, _author);
        }
    }

    // placeHolder reserved for future usage
    uint256[50] private __reservedSlots;
}
