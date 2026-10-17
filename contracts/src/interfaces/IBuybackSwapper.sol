// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBuybackSwapper {
    /// @notice Pull `quoteIn` of the pool's quote asset from the caller and buy the pool's token.
    function buyExactIn(bytes32 poolId, uint256 quoteIn, uint256 minTokenOut, address to)
        external
        returns (uint256 tokenOut);
}
