// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolKey, SwapParams, ICLPoolManager, IVault, ILockCallback} from "../interfaces/IInfinity.sol";

/// @notice Stand-in for PancakeSwap Infinity's Vault and CLPoolManager in one contract, for tests and anvil.
/// Same lock / sync / settle / take flow and delta sign convention as the real vault. Pools are
/// constant-product with a 1% fee that accrues to the launchpad, like Ascend's hook fee.
contract MockAscendPool is IVault, ICLPoolManager {
    using SafeERC20 for IERC20;

    struct PoolState {
        PoolKey key;
        uint256 reserve0;
        uint256 reserve1;
        uint256 fees0;
        uint256 fees1;
        bool exists;
    }

    uint256 public constant FEE_BPS = 100;

    address public launchpad;
    mapping(bytes32 => PoolState) internal _pools;

    address internal _locker;
    address[] internal _touched;
    mapping(address => int256) internal _debt; // positive = locker owes the vault
    address internal _synced;
    uint256 internal _syncedReserve;

    error OnlyLaunchpad();
    error OnlyLocker();
    error AlreadyLocked();
    error CurrencyNotSettled();
    error UnknownPool();
    error ExactOutputUnsupported();
    error NothingSynced();

    function setLaunchpad(address launchpad_) external {
        require(launchpad == address(0), "set");
        launchpad = launchpad_;
    }

    modifier onlyLaunchpad() {
        if (msg.sender != launchpad) revert OnlyLaunchpad();
        _;
    }

    modifier onlyLocker() {
        if (msg.sender != _locker) revert OnlyLocker();
        _;
    }

    // ------------------------------------------------------------ launchpad hooks

    function initPool(PoolKey calldata key, uint256 reserve0, uint256 reserve1) external onlyLaunchpad returns (bytes32 id) {
        id = keccak256(abi.encode(key));
        PoolState storage p = _pools[id];
        p.key = key;
        p.reserve0 = reserve0;
        p.reserve1 = reserve1;
        p.exists = true;
    }

    function addFees(bytes32 id, uint256 fees0, uint256 fees1) external onlyLaunchpad {
        PoolState storage p = _pool(id);
        p.fees0 += fees0;
        p.fees1 += fees1;
    }

    function withdrawFees(bytes32 id, address to) external onlyLaunchpad returns (uint256 f0, uint256 f1) {
        PoolState storage p = _pool(id);
        (f0, f1) = (p.fees0, p.fees1);
        p.fees0 = 0;
        p.fees1 = 0;
        if (f0 > 0) IERC20(p.key.currency0).safeTransfer(to, f0);
        if (f1 > 0) IERC20(p.key.currency1).safeTransfer(to, f1);
    }

    // ------------------------------------------------------------ vault

    function lock(bytes calldata data) external returns (bytes memory result) {
        if (_locker != address(0)) revert AlreadyLocked();
        _locker = msg.sender;
        result = ILockCallback(msg.sender).lockAcquired(data);
        for (uint256 i; i < _touched.length; ++i) {
            if (_debt[_touched[i]] != 0) revert CurrencyNotSettled();
        }
        delete _touched;
        _locker = address(0);
    }

    function sync(address currency) external {
        _synced = currency;
        _syncedReserve = IERC20(currency).balanceOf(address(this));
    }

    function settle() external payable onlyLocker returns (uint256 paid) {
        if (_synced == address(0)) revert NothingSynced();
        paid = IERC20(_synced).balanceOf(address(this)) - _syncedReserve;
        _addDebt(_synced, -int256(paid));
        _synced = address(0);
    }

    function take(address currency, address to, uint256 amount) external onlyLocker {
        _addDebt(currency, int256(amount));
        IERC20(currency).safeTransfer(to, amount);
    }

    // ------------------------------------------------------------ pool manager

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata)
        external
        onlyLocker
        returns (int256 delta)
    {
        bytes32 id = keccak256(abi.encode(key));
        PoolState storage p = _pool(id);
        if (params.amountSpecified >= 0) revert ExactOutputUnsupported();
        uint256 amountIn = uint256(-params.amountSpecified);
        uint256 fee = amountIn * FEE_BPS / 10_000;
        uint256 inAfterFee = amountIn - fee;

        int128 a0;
        int128 a1;
        if (params.zeroForOne) {
            uint256 out = p.reserve1 * inAfterFee / (p.reserve0 + inAfterFee);
            p.reserve0 += inAfterFee;
            p.reserve1 -= out;
            p.fees0 += fee;
            _addDebt(key.currency0, int256(amountIn));
            _addDebt(key.currency1, -int256(out));
            a0 = -int128(int256(amountIn));
            a1 = int128(int256(out));
        } else {
            uint256 out = p.reserve0 * inAfterFee / (p.reserve1 + inAfterFee);
            p.reserve1 += inAfterFee;
            p.reserve0 -= out;
            p.fees1 += fee;
            _addDebt(key.currency1, int256(amountIn));
            _addDebt(key.currency0, -int256(out));
            a0 = int128(int256(out));
            a1 = -int128(int256(amountIn));
        }
        delta = (int256(a0) << 128) | int256(uint256(uint128(a1)));
    }

    function getSlot0(bytes32 id) external view returns (uint160 sqrtPriceX96, int24, uint24, uint24) {
        PoolState storage p = _pool(id);
        sqrtPriceX96 = uint160(Math.sqrt(Math.mulDiv(p.reserve1, 1 << 192, p.reserve0)));
        return (sqrtPriceX96, 0, 0, 10_000);
    }

    function poolIdToPoolKey(bytes32 id)
        external
        view
        returns (address, address, address, address, uint24, bytes32)
    {
        PoolKey storage k = _pool(id).key;
        return (k.currency0, k.currency1, k.hooks, k.poolManager, k.fee, k.parameters);
    }

    function reserves(bytes32 id) external view returns (uint256, uint256, uint256, uint256) {
        PoolState storage p = _pool(id);
        return (p.reserve0, p.reserve1, p.fees0, p.fees1);
    }

    function _pool(bytes32 id) internal view returns (PoolState storage p) {
        p = _pools[id];
        if (!p.exists) revert UnknownPool();
    }

    function _addDebt(address currency, int256 amount) internal {
        if (_debt[currency] == 0 && amount != 0) _touched.push(currency);
        _debt[currency] += amount;
    }
}
