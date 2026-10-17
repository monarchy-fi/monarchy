// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISandfall {
    function createRolling(address asset, address recipient, uint32 window, address creator, bool cancellable)
        external
        returns (uint256 id);

    function topUp(uint256 id, uint128 amount) external payable;
}
