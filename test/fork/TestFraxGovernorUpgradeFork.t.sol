// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../TestFraxGovernorUpgrade.t.sol";

contract TestFraxGovernorUpgradeFork is TestFraxGovernorUpgrade {
    function setUp() public override {
        _forkSetUp();
        _upgradeSetUp();
    }
}
