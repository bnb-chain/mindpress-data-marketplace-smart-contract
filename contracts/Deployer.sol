// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "./Marketplace.sol";
import "./MarketplaceBadge.sol";

contract Deployer {
    address public proxyAdmin;
    address public proxyBadge;
    address public implBadge;
    address public proxyMarketplace;
    address public implMarketplace;

    bool public deployed;

    constructor() {
        /*
            @dev deploy workflow
            a. Generate contracts addresses in advance first while deploy `Deployer`
            c. Deploy the proxy contracts, checking if they are equal to the generated addresses before
        */
        proxyAdmin = calcCreateAddress(address(this), uint8(1));
        proxyBadge = calcCreateAddress(address(this), uint8(2));
        proxyMarketplace = calcCreateAddress(address(this), uint8(3));

        address deployedProxyAdmin = address(new ProxyAdmin());
        require(deployedProxyAdmin == proxyAdmin, "invalid proxyAdmin address");
    }

    function deploy(
        address _implBadge,
        address _implMarketplace,
        address _owner,
        address _fundWallet,
        uint256 _tax,
        uint256 _callbackGasLimit,
        uint8 _failureHandleStrategy
    ) public {
        require(!deployed, "only not deployed");
        deployed = true;

        require(_owner != address(0), "invalid owner");
        require(_fundWallet != address(0), "invalid fundWallet");
        require(_tax <= 1000, "invalid tax");
        require(_callbackGasLimit > 0, "invalid callbackGasLimit");

        require(_isContract(_implBadge), "invalid implBadge");
        implBadge = _implBadge;
        require(_isContract(_implMarketplace), "invalid implMarketplace");
        implMarketplace = _implMarketplace;

        // 1. deploy proxy badge contract
        address deployedProxyBadge = address(new TransparentUpgradeableProxy(implBadge, proxyAdmin, ""));
        require(deployedProxyBadge == proxyBadge, "invalid proxyBadge address");

        // 2. deploy proxy marketplace contract
        address deployedProxyMarketplace = address(new TransparentUpgradeableProxy(implMarketplace, proxyAdmin, ""));
        require(deployedProxyMarketplace == proxyMarketplace, "invalid proxyMarketplace address");

        // 3. transfer admin ownership
        ProxyAdmin(proxyAdmin).transferOwnership(_owner);
        require(ProxyAdmin(proxyAdmin).owner() == _owner, "invalid proxyAdmin owner");

        // 4. init
        MarketplaceBadge(proxyBadge).initialize("", proxyMarketplace, _owner);
        Marketplace(payable(proxyMarketplace)).initialize(
            _owner, _fundWallet, _tax, proxyBadge, _callbackGasLimit, _failureHandleStrategy
        );
    }

    function calcCreateAddress(address _deployer, uint8 _nonce) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _deployer, _nonce)))));
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
