// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../TestVeFxsVotingDelegation.t.sol";

contract TestVeFxsVotingDelegationFork is TestVeFxsVotingDelegation {
    function setUp() public override {
        _forkSetUp();
    }

    // only run locally
    function testBoundsOfDelegationStructs() public override {}

    // only run locally
    function testFuzzManyCheckpoints(uint256 daysDelta, uint256 timestamp) public override {}

    // only run locally
    function testCheckpoints() public override {}
}
