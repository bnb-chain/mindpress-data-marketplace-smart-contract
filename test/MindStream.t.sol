// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "../contracts/Deployer.sol";
import "../contracts/MindStream.sol";

contract MindStreamTest is Test {
    uint256 public constant callbackGasLimit = 1_000_000; // TODO: TBD
    uint8 public constant failureHandleStrategy = 0; // BlockOnFail
    uint256 public constant tax = 100; // 1%

    address public operator;
    address public proxyMindStream;

    address public owner;
    address public crossChain;
    address public groupHub;
    address public groupToken;

    event ProfileCreated(address indexed author);
    event UpdateSubmitted(address owner, address operator, uint256 id, uint8 opType, address[] members);

    receive() external payable {}

    function setUp() public {
        proxyMindStream = 0x55c72Fa6405ECf270bDBF33aa7f87E3189C076E3; // get this from deploy script's log
        crossChain = MindStream(proxyMindStream)._CROSS_CHAIN();
        groupHub = MindStream(proxyMindStream)._GROUP_HUB();
        groupToken = MindStream(proxyMindStream)._GROUP_TOKEN();
    }

    function testUpdateProfile() public {
        // failed with empty name when not created
        vm.expectRevert("MindStream: invalid name");
        MindStream(proxyMindStream).updateProfile("", "test", "test");

        // success case
        vm.expectEmit(true, false, false, true, proxyMindStream);
        emit ProfileCreated(address(this));
        MindStream(proxyMindStream).updateProfile("test", "test", "test");

        // success case
        MindStream(proxyMindStream).updateProfile("test1", "test2", "test3");
        (string memory _name, string memory _avatar, string memory _bio,) =
            MindStream(proxyMindStream).profileByAddress(address(this));
        assertEq(_name, "test1");
        assertEq(_avatar, "test2");
        assertEq(_bio, "test3");
    }

    function testSubscribe() public {
        address _author = address(0x1234);
        vm.prank(_author);
        MindStream(proxyMindStream).updateProfile("test", "test", "test");

        // failed with no subscribeID
        vm.expectRevert("MindStream: not subscribable");
        MindStream(proxyMindStream).subscribeOrRenew(_author, MindStream.TypesOfSubscriptions.OneMonth);

        uint256 groupId = 97;
        vm.prank(groupHub);
        IERC721NonTransferable(groupToken).mint(_author, groupId);

        uint256[3] memory _prices = [uint256(1 ether), uint256(2 ether), uint256(3 ether)];
        vm.startPrank(_author);
        ICmnHub(groupHub).grant(proxyMindStream, 4, 0);
        MindStream(proxyMindStream).openUpSubscribeChannel(groupId, _prices);
        vm.stopPrank();

        // failed with not enough fund
        vm.expectRevert("MindStream: insufficient fund");
        MindStream(proxyMindStream).subscribeOrRenew{value: 1 ether}(_author, MindStream.TypesOfSubscriptions.OneMonth);

        // success case
        uint256 relayFee = _getTotalFee();
        address[] memory members = new address[](1);
        members[0] = address(this);
        vm.expectEmit(true, true, true, true, groupHub);
        emit UpdateSubmitted(_author, proxyMindStream, groupId, 0, members);
        MindStream(proxyMindStream).subscribeOrRenew{value: 1 ether + relayFee}(
            _author, MindStream.TypesOfSubscriptions.OneMonth
        );
    }

    function _getTotalFee() internal returns (uint256) {
        (uint256 relayFee, uint256 minAckRelayFee) = ICrossChain(crossChain).getRelayFees();
        uint256 gasPrice = ICrossChain(crossChain).callbackGasPrice();
        return relayFee + minAckRelayFee + callbackGasLimit * gasPrice;
    }
}
