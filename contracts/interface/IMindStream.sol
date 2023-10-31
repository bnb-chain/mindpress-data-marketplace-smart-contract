pragma solidity ^0.8.0;

interface IMindStream {
    event AppHandleAckPkgFailed(address indexed appAddress, bytes32 pkgHash, bytes failReason);
    event AppHandleFailAckPkgFailed(address indexed appAddress, bytes32 pkgHash, bytes failReason);
    event CreateFailed(address indexed creator, uint256 indexed id);
    event CreateGroupFailed(uint32 status, bytes groupName);
    event CreateGroupSuccess(bytes groupName, uint256 indexed tokenId);
    event CreateSubmitted(address indexed owner, address indexed operator, string name);
    event CreateSuccess(address indexed creator, uint256 indexed id);
    event DeleteFailed(uint256 indexed id);
    event DeleteGroupFailed(uint32 status, uint256 indexed tokenId);
    event DeleteGroupSuccess(uint256 indexed tokenId);
    event DeleteSubmitted(address indexed owner, address indexed operator, uint256 indexed id);
    event DeleteSuccess(uint256 indexed id);
    event FailAckPkgReceived(uint8 indexed channelId, bytes msgBytes);
    event Initialized(uint8 version);
    event MirrorFailed(uint256 indexed id, address indexed owner, bytes failReason);
    event MirrorSuccess(uint256 indexed id, address indexed owner);
    event ParamChange(string key, bytes value);
    event Post(address indexed author, uint256 indexed visibility, string url);
    event ProfileCreated(address indexed author);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Subscribe(address indexed subscriber, address indexed author);
    event SubscribeFailed(address indexed subscriber, address indexed author);
    event UnexpectedPackage(uint8 indexed channelId, bytes msgBytes);
    event UpdateFailed(address indexed operator, uint256 indexed id, uint8 opType);
    event UpdateGroupFailed(uint32 status, uint256 indexed tokenId);
    event UpdateGroupSuccess(uint256 indexed tokenId);
    event UpdateSubmitted(address owner, address operator, uint256 id, uint8 opType, address[] members);
    event UpdateSuccess(address indexed operator, uint256 indexed id, uint8 opType);

    struct PersonalSettings {
        uint256 subscribeID;
        uint256[3] prices;
    }

    struct Profile {
        string name;
        string avatar;
        string bio;
        uint256 createTime;
    }

    struct Statistics {
        uint256 salesVolume;
        uint256 salesRevenue;
    }

    function AUTH_CODE_CREATE() external view returns (uint32);
    function AUTH_CODE_DELETE() external view returns (uint32);
    function AUTH_CODE_UPDATE() external view returns (uint32);
    function BUCKET_CHANNEL_ID() external view returns (uint8);
    function BUCKET_HUB() external view returns (address);
    function CROSS_CHAIN() external view returns (address);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function EMERGENCY_OPERATOR() external view returns (address);
    function EMERGENCY_UPGRADE_OPERATOR() external view returns (address);
    function ERC1155Token() external view returns (address);
    function ERC721Token() external view returns (address);
    function ERROR_INSUFFICIENT_VALUE() external view returns (string memory);
    function ERROR_INVALID_CALLER() external view returns (string memory);
    function ERROR_INVALID_OPERATION() external view returns (string memory);
    function ERROR_INVALID_RESOURCE() external view returns (string memory);
    function GOV_CHANNEL_ID() external view returns (uint8);
    function GOV_HUB() external view returns (address);
    function GROUP_CHANNEL_ID() external view returns (uint8);
    function GROUP_HUB() external view returns (address);
    function INIT_MAX_CALLBACK_DATA_LENGTH() external view returns (uint256);
    function LIGHT_CLIENT() external view returns (address);
    function MAX_CALLBACK_GAS_LIMIT() external view returns (uint256);
    function OBJECT_CHANNEL_ID() external view returns (uint8);
    function OBJECT_HUB() external view returns (address);
    function ONE_MONTH() external view returns (uint64);
    function ONE_YEAR() external view returns (uint64);
    function OPERATOR_ROLE() external view returns (bytes32);
    function PROXY_ADMIN() external view returns (address);
    function RELAYER_HUB() external view returns (address);
    function RESOURCE_GROUP() external view returns (uint8);
    function ROLE_CREATE() external view returns (bytes32);
    function ROLE_DELETE() external view returns (bytes32);
    function ROLE_UPDATE() external view returns (bytes32);
    function STATUS_FAILED() external view returns (uint32);
    function STATUS_SUCCESS() external view returns (uint32);
    function STATUS_UNEXPECTED() external view returns (uint32);
    function THREE_MONTHS() external view returns (uint64);
    function TOKEN_HUB() external view returns (address);
    function TRANSFER_IN_CHANNEL_ID() external view returns (uint8);
    function TRANSFER_OUT_CHANNEL_ID() external view returns (uint8);
    function TYPE_CREATE() external view returns (uint8);
    function TYPE_DELETE() external view returns (uint8);
    function TYPE_MIRROR() external view returns (uint8);
    function TYPE_UPDATE() external view returns (uint8);
    function _CROSS_CHAIN() external view returns (address);
    function _GROUP_HUB() external view returns (address);
    function _GROUP_TOKEN() external view returns (address);
    function _MEMBER_TOKEN() external view returns (address);
    function addOperator(address newOperator) external;
    function additional() external view returns (address);
    function callbackGasLimit() external view returns (uint256);
    function channelId() external view returns (uint8);
    function claim() external;
    function crossChain() external view returns (address);
    function failureHandleStrategy() external view returns (uint8);
    function feeRate() external view returns (uint256);
    function fundWallet() external view returns (address);
    function getMinRelayFee() external returns (uint256 amount);
    function getProfileByAddress(address _author)
        external
        view
        returns (string memory _name, string memory _avatar, string memory _bio, uint256 _createTime);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getSalesRevenueRanking() external view returns (address[] memory _addrs, uint256[] memory _revenues);
    function getSalesVolumeRanking() external view returns (address[] memory _addrs, uint256[] memory _volumes);
    function getStatusByAddress(address _author)
        external
        view
        returns (uint256 _subscribeID, uint256[3] memory _prices, uint256 _salesVolume, uint256 _salesRevenue);
    function getSubscribableAuthors(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory _authors, uint256 _totalLength);
    function getUnclaimedAmount() external view returns (uint256 amount);
    function getUserSubscribed(address user, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory _authors, uint64[] memory _expirations, uint256 _totalLength);
    function getUsersInfo(uint256 offset, uint256 limit)
        external
        view
        returns (
            address[] memory _addrs,
            Profile[] memory _profiles,
            PersonalSettings[] memory _settings,
            Statistics[] memory _statistics,
            uint256 _totalLength
        );
    function grantRole(bytes32 role, address account) external;
    function greenfieldCall(
        uint32 status,
        uint8 resourceType,
        uint8 operationType,
        uint256 resourceId,
        bytes memory callbackData
    ) external;
    function groupHub() external view returns (address);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initialize(
        address _initAdmin,
        address _fundWallet,
        uint256 _feeRate,
        uint256 _callbackGasLimit,
        uint8 _failureHandleStrategy
    ) external;
    function maxCallbackDataLength() external view returns (uint256);
    function openUpSubscribeChannel(uint256 _groupId, uint256[3] memory _prices) external;
    function packageMap(bytes32)
        external
        view
        returns (
            address appAddress,
            uint32 status,
            uint8 operationType,
            uint256 resourceId,
            bytes memory callbackData,
            bytes memory failReason
        );
    function removeOperator(address operator) external;
    function renounceRole(bytes32 role, address account) external;
    function retryPackage(uint8) external;
    function retryQueue(address) external view returns (int128 _begin, int128 _end);
    function revokeRole(bytes32 role, address account) external;
    function setCallbackGasLimit(uint256 _callbackGasLimit) external;
    function setFailureHandleStrategy(uint8 _failureHandleStrategy) external;
    function setFeeRate(uint256 _feeRate) external;
    function setFundWallet(address _fundWallet) external;
    function setPrice(uint256[3] memory _prices) external;
    function setTransferGasLimit(uint256 _transferGasLimit) external;
    function skipPackage(uint8) external;
    function subscribeOrRenew(address _author, uint8 _type) external payable;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function transferGasLimit() external view returns (uint256);
    function updateProfile(string memory _name, string memory _avatar, string memory _bio) external;
    function versionInfo() external pure returns (uint256 version, string memory name, string memory description);
}
