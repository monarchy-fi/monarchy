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
///      listing set-aside and optionally locks the creator role.
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
        uint64 creatorLockUntil;
    }

    address public immutable implementation;
    IAscendLaunchpad public immutable launchpad;
    IListingDesk public immutable desk;
    ICLPoolManager public immutable poolManager;
    IExile public immutable exile;
    ISandfall public immutable sandfall;

    address public owner;
    address public defaultSwapper;
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
    event OwnerTransferred(address indexed previous, address indexed next);

    error DeskMismatch();
    error NotPoolCreator();
    error TransferCreatorFirst();
    error OnlyOwner();
    error ZeroAddress();

    constructor(
        address implementation_,
        IAscendLaunchpad launchpad_,
        IListingDesk desk_,
        ICLPoolManager poolManager_,
        IExile exile_,
        ISandfall sandfall_,
        address defaultSwapper_
    ) {
        if (launchpad_.listingDesk() != address(desk_)) revert DeskMismatch();
        implementation = implementation_;
        launchpad = launchpad_;
        desk = desk_;
        poolManager = poolManager_;
        exile = exile_;
        sandfall = sandfall_;
        owner = msg.sender;
        defaultSwapper = defaultSwapper_;
        emit DefaultSwapperSet(defaultSwapper_);
    }

    /// @notice The router address and Ascend pool id for a token, before or after deployment.
    function predict(address token, address quote) public view returns (address lodestar, bytes32 poolId) {
        poolId = AscendPoolKey.id(token, quote, address(launchpad), address(poolManager));
        lodestar = Clones.predictDeterministicAddress(implementation, poolId, address(this));
    }

    /// @notice Activate a Lodestar. Caller must be the pool's current Ascend creator and must already
    /// have called `transferCreator(poolId, predicted)` on Ascend. Send at least 3M gas when
    /// `enrolListing` is set (Ascend's desk checks a gas floor).
    function deploy(DeployParams calldata p) external returns (address lodestar) {
        bytes32 poolId;
        (lodestar, poolId) = predict(p.token, p.quote);
        if (launchpad.poolCreator(poolId) != msg.sender) revert NotPoolCreator();
        if (launchpad.pendingCreator(poolId) != lodestar) revert TransferCreatorFirst();
        if (p.treasuryRecipient == address(0)) revert ZeroAddress();

        Clones.cloneDeterministic(implementation, poolId);
        uint256 exilePoolId = exile.createPool(p.token, p.quote, p.tiers, msg.sender);
        uint256 streamId = sandfall.createRolling(p.quote, p.treasuryRecipient, p.treasuryWindow, lodestar, false);

        ILodestar.Config memory cfg = p.cfg;
        if (cfg.swapper == address(0)) cfg.swapper = defaultSwapper;

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
        emit DefaultSwapperSet(swapper);
    }

    function transferOwner(address next) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (next == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, next);
        owner = next;
    }
}
