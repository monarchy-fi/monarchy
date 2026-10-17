// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal PancakeSwap Infinity types and interfaces used by Ascend pools.
struct PoolKey {
    address currency0;
    address currency1;
    address hooks;
    address poolManager;
    uint24 fee;
    bytes32 parameters;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified; // negative = exact input
    uint160 sqrtPriceLimitX96;
}

interface ICLPoolManager {
    /// @return delta amount0 in the high 128 bits, amount1 in the low 128 bits; positive = owed to caller.
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 delta);

    function getSlot0(bytes32 id)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

    function poolIdToPoolKey(bytes32 id)
        external
        view
        returns (
            address currency0,
            address currency1,
            address hooks,
            address poolManager,
            uint24 fee,
            bytes32 parameters
        );
}

interface IVault {
    function lock(bytes calldata data) external returns (bytes memory);
    function sync(address currency) external;
    function settle() external payable returns (uint256 paid);
    function take(address currency, address to, uint256 amount) external;
}

interface ILockCallback {
    function lockAcquired(bytes calldata data) external returns (bytes memory);
}
