// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../TestFraxGovernor.t.sol";

contract TestFraxGovernorFork is TestFraxGovernor {
    function setUp() public override {
        _forkSetUp();
    }
}
