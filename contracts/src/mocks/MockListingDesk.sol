// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IListingDesk} from "../interfaces/IListingDesk.sol";
import {AscendPoolKey} from "../libraries/AscendPoolKey.sol";
import {MockAscendLaunchpad} from "./MockAscendLaunchpad.sol";

/// @notice Stand-in for Ascend's ListingDesk: enroll / close / withdraw with the same access rules
/// and the same collect-gas floor. Listing delivery itself is out of scope for the mock.
contract MockListingDesk is IListingDesk {
    uint256 public constant COLLECT_GAS_FLOOR = 2_000_000;

    MockAscendLaunchpad public immutable launchpad;
    address public immutable poolManager;
    mapping(address => bytes32) public poolOf;

    error Unauthorized();
    error InvalidCap();
    error InsufficientCollectGas();
    error ElectionLive();
    error NoElection();
    error NotListed();

    constructor(MockAscendLaunchpad launchpad_) {
        launchpad = launchpad_;
        poolManager = address(launchpad_.pool());
        launchpad_.setListingDesk(address(this));
    }

    function register(address token, address quote) public returns (bytes32 id) {
        id = AscendPoolKey.id(token, quote, address(launchpad), poolManager);
        if (launchpad.poolCreator(id) == address(0)) revert Unauthorized();
        poolOf[token] = id;
    }

    function enroll(address token, address quote, uint256 cap) external {
        bytes32 id = register(token, quote);
        if (msg.sender != launchpad.poolCreator(id)) revert Unauthorized();
        if (cap == 0 || cap > type(uint88).max) revert InvalidCap();
        if (gasleft() < COLLECT_GAS_FLOOR) revert InsufficientCollectGas();
        launchpad.collect(id); // fees earned before enrolling stay with the creator
        launchpad.setListing(id, msg.sender, cap);
    }

    function close(bytes32 id) external {
        address creator = launchpad.poolCreator(id);
        if (msg.sender != creator) revert Unauthorized();
        if (!_live(id, creator)) revert NoElection();
        launchpad.collect(id);
        launchpad.setListing(id, address(0), 0);
    }

    function withdraw(bytes32 id, uint256 amount) external {
        address creator = launchpad.poolCreator(id);
        if (_live(id, creator)) revert ElectionLive();
        launchpad.takeListing(id, creator, amount);
    }

    function splitCoreFees(address) external pure {
        revert NotListed();
    }

    function _live(bytes32 id, address creator) internal view returns (bool) {
        uint256 e = launchpad.listingElection(id);
        return e != 0 && address(uint160(e)) == creator;
    }
}
