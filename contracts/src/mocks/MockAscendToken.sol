// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";

/// @notice Mirrors a quirk of Ascend's launch tokens seen on Elysium testnet: transfers to address(0)
/// or the conventional 0x…dEaD burn address revert with InvalidRecipient().
contract MockAscendToken is MockERC20 {
    error InvalidRecipient();

    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to == 0x000000000000000000000000000000000000dEaD) revert InvalidRecipient();
        super._update(from, to, value);
    }
}
