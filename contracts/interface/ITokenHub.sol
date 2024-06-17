// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface ITokenHub {
    function transferOut(address recipient, uint256 amount) external payable returns (bool);
}
