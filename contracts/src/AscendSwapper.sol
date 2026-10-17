// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAscendLaunchpad} from "./interfaces/IAscendLaunchpad.sol";
import {IBuybackSwapper} from "./interfaces/IBuybackSwapper.sol";
import {PoolKey, SwapParams, ICLPoolManager, IVault, ILockCallback} from "./interfaces/IInfinity.sol";

/// @title AscendSwapper
/// @notice Exact-input swaps on Ascend pools through PancakeSwap Infinity's vault. Lodestar uses
/// `buyExactIn` for buybacks; `sellExactIn` is there for demo volume. Holds no funds between calls.
contract AscendSwapper is IBuybackSwapper, ILockCallback, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint160 internal constant MIN_SQRT_PRICE_LIMIT = 4295128740;
    uint160 internal constant MAX_SQRT_PRICE_LIMIT = 1461446703485210103287273052203988822378723970341;

    IVault public immutable vault;
    ICLPoolManager public immutable poolManager;
    IAscendLaunchpad public immutable launchpad;

    struct Op {
        bytes32 poolId;
        bool isBuy;
        uint256 amountIn;
        uint256 minOut;
        address to;
    }

    event Swapped(bytes32 indexed poolId, address indexed sender, bool isBuy, uint256 amountIn, uint256 amountOut, address to);

    error OnlyVault();
    error Slippage(uint256 out, uint256 minOut);
    error ZeroAmount();
    error UnexpectedDelta();

    constructor(IVault vault_, ICLPoolManager poolManager_, IAscendLaunchpad launchpad_) {
        vault = vault_;
        poolManager = poolManager_;
        launchpad = launchpad_;
    }

    /// @inheritdoc IBuybackSwapper
    function buyExactIn(bytes32 poolId, uint256 quoteIn, uint256 minTokenOut, address to)
        external
        nonReentrant
        returns (uint256 tokenOut)
    {
        tokenOut = _swap(Op(poolId, true, quoteIn, minTokenOut, to));
    }

    /// @notice Sell `tokenIn` of the pool's token for its quote asset.
    function sellExactIn(bytes32 poolId, uint256 tokenIn, uint256 minQuoteOut, address to)
        external
        nonReentrant
        returns (uint256 quoteOut)
    {
        quoteOut = _swap(Op(poolId, false, tokenIn, minQuoteOut, to));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(vault)) revert OnlyVault();
        Op memory op = abi.decode(data, (Op));

        PoolKey memory key;
        (key.currency0, key.currency1, key.hooks, key.poolManager, key.fee, key.parameters) =
            poolManager.poolIdToPoolKey(op.poolId);
        bool tokenIs0 = launchpad.poolTokenIs0(op.poolId);
        // buying the token = paying quote; zeroForOne when quote is currency0
        bool zeroForOne = op.isBuy ? !tokenIs0 : tokenIs0;

        int256 delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(op.amountIn),
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE_LIMIT : MAX_SQRT_PRICE_LIMIT
            }),
            ""
        );
        int128 a0 = int128(delta >> 128);
        int128 a1 = int128(delta);
        (int128 dIn, int128 dOut) = zeroForOne ? (a0, a1) : (a1, a0);
        if (dIn > 0 || dOut < 0) revert UnexpectedDelta();
        uint256 paid = uint256(uint128(-dIn));
        uint256 out = uint256(uint128(dOut));
        if (out < op.minOut) revert Slippage(out, op.minOut);

        (address cIn, address cOut) = zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
        if (paid > 0) {
            vault.sync(cIn);
            IERC20(cIn).safeTransfer(address(vault), paid);
            vault.settle();
        }
        if (out > 0) vault.take(cOut, op.to, out);
        return abi.encode(paid, out);
    }

    function _swap(Op memory op) internal returns (uint256 out) {
        if (op.amountIn == 0) revert ZeroAmount();
        (address c0, address c1,,,,) = poolManager.poolIdToPoolKey(op.poolId);
        bool tokenIs0 = launchpad.poolTokenIs0(op.poolId);
        address cIn = (op.isBuy != tokenIs0) ? c0 : c1; // buy: pay quote; sell: pay token
        IERC20(cIn).safeTransferFrom(msg.sender, address(this), op.amountIn);

        uint256 paid;
        (paid, out) = abi.decode(vault.lock(abi.encode(op)), (uint256, uint256));
        // a price limit can stop a swap early; return what the pool didn't take
        if (paid < op.amountIn) IERC20(cIn).safeTransfer(msg.sender, op.amountIn - paid);
        emit Swapped(op.poolId, msg.sender, op.isBuy, paid, out, op.to);
    }
}
