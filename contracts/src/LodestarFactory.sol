// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IAscendLaunchpad} from "./interfaces/IAscendLaunchpad.sol";
import {IListingDesk} from "./interfaces/IListingDesk.sol";
import {ICLPoolManager} from "./interfaces/IInfinity.sol";
import {IExile} from "./interfaces/IExile.sol";
import {ISandfall} from "./interfaces/ISandfall.sol";
import {ILodestar} from "./interfaces/ILodestar.sol";
import {AscendPoolKey} from "./libraries/AscendPoolKey.sol";

/// @title LodestarFactory
/// @notice Deploys one Lodestar router per Ascend pool at an address anyone can predict from the
/// token and quote. Activation flow for a dev who launched on Ascend's site:
///   1. `predict(token, quote)` to get the router address.
///   2. On Ascend: `transferCreator(poolId, router)`.
///   3. Here: `deploy(params)`. In one transaction this creates the router, its Exile holder-rewards
///      pool and its Sandfall Team Treasury stream, accepts the creator role, optionally enrols the
///      listing set-aside and, if the dev chose so, locks the creator role to the router forever.
/// The dev keeps the dev-buy tokens; only the creator fee stream moves to the router.
contract LodestarFactory {
    struct DeployParams {
        address token;
        address quote;
        ILodestar.Config cfg;
        address treasuryRecipient;
        uint32 treasuryWindow;
        IExile.Tier[] tiers;
        bool enrolListing;
        uint256 listingCap;
        /// @dev When the creator role unlocks: 0 = no lock, type(uint64).max = locked for good.
        uint64 creatorLockUntil;
    }

    address public immutable implementation;
    IAscendLaunchpad public immutable launchpad;
    IListingDesk public immutable desk;
    ICLPoolManager public immutable poolManager;
    IExile public immutable exile;
    ISandfall public immutable sandfall;

    /// @notice Names the successor factory for upgrades and the default swapper for new activations. A multisig
    /// in production, separate from every steward, so no single key can start an upgrade.
    address public owner;
    /// @notice The owner role's next holder until it accepts (0 = no handover pending).
    address public pendingOwner;
    address public defaultSwapper;
    /// @notice When the default swapper last changed. A new default only applies to deploys 12 hours
    /// later, so it can't be swapped in between a dev's `transferCreator` and `deploy`.
    uint64 public defaultSwapperSetAt;
    uint64 public constant DEFAULT_SWAPPER_DELAY = 12 hours;
    /// @notice A newer Monarchy factory that routers made here may move their creator role to, once each,
    /// with 7 days' notice. The owner names it, and each router's steward still has to propose the move.
    /// 0 = none.
    address public successor;
    mapping(address token => address) public lodestarOf;
    address[] public allLodestars;

    event LodestarDeployed(
        address indexed token,
        bytes32 indexed poolId,
        address lodestar,
        address indexed steward,
        uint256 exilePoolId,
        uint256 treasuryStreamId
    );
    event DefaultSwapperSet(address swapper);
    event SuccessorSet(address successor);
    event OwnerTransferStarted(address indexed next);
    event OwnerTransferred(address indexed previous, address indexed next);

    error DeskMismatch();
    error NotPoolCreator();
    error TransferCreatorFirst();
    error OnlyOwner();
    error ZeroAddress();
    error WrongTokenOrder();
    error DefaultSwapperJustChanged();
    error AlreadyDeployed();
    error NotPendingOwner();

    constructor(
        address implementation_,
        IAscendLaunchpad launchpad_,
        IListingDesk desk_,
        ICLPoolManager poolManager_,
        IExile exile_,
        ISandfall sandfall_,
        address defaultSwapper_,
        address owner_
    ) {
        if (launchpad_.listingDesk() != address(desk_)) revert DeskMismatch();
        if (owner_ == address(0)) revert ZeroAddress();
        implementation = implementation_;
        launchpad = launchpad_;
        desk = desk_;
        poolManager = poolManager_;
        exile = exile_;
        sandfall = sandfall_;
        owner = owner_;
        defaultSwapper = defaultSwapper_;
        emit OwnerTransferred(address(0), owner_);
        emit DefaultSwapperSet(defaultSwapper_);
    }

    /// @notice The router address and Ascend pool id for a token, before or after deployment.
    function predict(address token, address quote) public view returns (address lodestar, bytes32 poolId) {
        poolId = AscendPoolKey.id(token, quote, address(launchpad), address(poolManager));
        lodestar = Clones.predictDeterministicAddress(implementation, poolId, address(this));
    }

    /// @notice Activate a Lodestar. Caller must be the pool's current Ascend creator and must already
    /// have called `transferCreator(poolId, predicted)` on Ascend. Send about 6M gas when
    /// `enrolListing` is set (Ascend's desk checks a gas floor).
    function deploy(DeployParams calldata p) external returns (address lodestar) {
        bytes32 poolId;
        (lodestar, poolId) = predict(p.token, p.quote);
        if (launchpad.poolCreator(poolId) != msg.sender) revert NotPoolCreator();
        if (launchpad.pendingCreator(poolId) != lodestar) revert TransferCreatorFirst();
        if (p.treasuryRecipient == address(0)) revert ZeroAddress();
        // the pool id sorts the pair, so check token and quote weren't passed the wrong way round
        if (launchpad.poolTokenIs0(poolId) != (p.token < p.quote)) revert WrongTokenOrder();
        // a second deploy would collide on CREATE2, which burns all the gas sent; fail cheaply instead.
        // To take the role back after it left, hand it to the existing router and call its acceptCreator.
        if (lodestar.code.length != 0) revert AlreadyDeployed();

        Clones.cloneDeterministic(implementation, poolId);
        // the router administers the reward pool, so tier changes stay with whoever is steward
        uint256 exilePoolId = exile.createPool(p.token, p.quote, p.tiers, lodestar);
        uint256 streamId = sandfall.createRolling(p.quote, p.treasuryRecipient, p.treasuryWindow, lodestar, false);

        ILodestar.Config memory cfg = p.cfg;
        if (cfg.swapper == address(0)) {
            if (block.timestamp < defaultSwapperSetAt + DEFAULT_SWAPPER_DELAY) revert DefaultSwapperJustChanged();
            cfg.swapper = defaultSwapper;
        }

        ILodestar(lodestar).initialize(
            ILodestar.InitParams({
                launchpad: address(launchpad),
                desk: address(desk),
                poolManager: address(poolManager),
                exile: address(exile),
                sandfall: address(sandfall),
                poolId: poolId,
                token: p.token,
                quote: p.quote,
                tokenIs0: launchpad.poolTokenIs0(poolId),
                exilePoolId: exilePoolId,
                treasuryStreamId: streamId,
                steward: msg.sender,
                config: cfg
            })
        );
        ILodestar(lodestar).acceptCreator();
        if (p.enrolListing) ILodestar(lodestar).enrollListing(p.listingCap);
        if (p.creatorLockUntil > 0) ILodestar(lodestar).lockCreatorRole(p.creatorLockUntil);

        lodestarOf[p.token] = lodestar;
        allLodestars.push(lodestar);
        emit LodestarDeployed(p.token, poolId, lodestar, msg.sender, exilePoolId, streamId);
    }

    function allLodestarsLength() external view returns (uint256) {
        return allLodestars.length;
    }

    // ---------------------------------------------------------------- owner

    /// @notice Buyback route used by future deploys that don't pick one. Existing routers are unaffected.
    function setDefaultSwapper(address swapper) external {
        if (msg.sender != owner) revert OnlyOwner();
        defaultSwapper = swapper;
        defaultSwapperSetAt = uint64(block.timestamp);
        emit DefaultSwapperSet(swapper);
    }

    /// @notice Name the newer factory that routers made here may upgrade to (0 clears it). Naming one moves
    /// nothing: a router's steward has to propose the move, and it waits 7 days. Changing or clearing the
    /// successor stops every pending move to the old one.
    function setSuccessor(address next) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (next == address(this)) revert ZeroAddress();
        successor = next;
        emit SuccessorSet(next);
    }

    /// @notice Start handing the owner role to `next`, which takes it with `acceptOwner`, so a mistyped address
    /// can't strand the role. Naming another address replaces a pending handover; 0 cancels it.
    function transferOwner(address next) external {
        if (msg.sender != owner) revert OnlyOwner();
        pendingOwner = next;
        emit OwnerTransferStarted(next);
    }

    function acceptOwner() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnerTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }
}
