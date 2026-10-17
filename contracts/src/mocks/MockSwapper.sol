// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBuybackSwapper} from "../interfaces/IBuybackSwapper.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice Fixed-price swapper for Lodestar unit tests, with a failure switch and an optional
/// re-entrancy probe.
contract MockSwapper is IBuybackSwapper {
    using SafeERC20 for IERC20;

    IERC20 public immutable quote;
    MockERC20 public immutable token;
    uint256 public tokensPerQuote; // 1e18-scaled
    bool public fail;
    address public reenterTarget;
    bytes public reenterData;

    constructor(IERC20 quote_, MockERC20 token_, uint256 tokensPerQuote_) {
        quote = quote_;
        token = token_;
        tokensPerQuote = tokensPerQuote_;
    }

    function setFail(bool f) external {
        fail = f;
    }

    function setReenter(address target, bytes calldata data) external {
        reenterTarget = target;
        reenterData = data;
    }

    function buyExactIn(bytes32, uint256 quoteIn, uint256 minTokenOut, address to) external returns (uint256 out) {
        require(!fail, "swap failed");
        if (reenterTarget != address(0)) {
            (bool ok, bytes memory ret) = reenterTarget.call(reenterData);
            if (!ok) {
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }
        quote.safeTransferFrom(msg.sender, address(this), quoteIn);
        out = quoteIn * tokensPerQuote / 1e18;
        require(out >= minTokenOut, "slippage");
        token.mint(to, out);
    }
}
