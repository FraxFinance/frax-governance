// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { Constants } from "../script/Constants.sol";
import { FraxGovernorAlpha, ConstructorParams as FraxAlphaGovernorParams } from "../src/FraxGovernorAlpha.sol";

function deployTimelockController(
    address admin
) returns (address payable _address, bytes memory _constructorParams, string memory _contractName) {
    uint256 minDelay = 1 days;
    address[] memory proposers = new address[](0);
    address[] memory executors = new address[](0);
    _constructorParams = abi.encode(minDelay, proposers, executors, admin);
    _contractName = "TimelockController";
    _address = payable(address(new TimelockController(minDelay, proposers, executors, admin)));
}

function deployFraxGovernorAlpha(
    address _veFxs,
    address _veFxsVotingDelegation,
    address payable _timelockController
) returns (address payable _address, bytes memory _constructorParams, string memory _contractName) {
    string memory name = "FraxGovernorAlpha";
    uint256 votingDelay = 2 days;
    FraxAlphaGovernorParams memory _params = FraxAlphaGovernorParams({
        name: name,
        veFxs: _veFxs,
        veFxsVotingDelegation: _veFxsVotingDelegation,
        timelockController: _timelockController,
        initialVotingDelay: votingDelay,
        initialVotingDelayBlocks: votingDelay / 12,
        initialVotingPeriod: 4 days,
        initialProposalThreshold: 100_000e18,
        quorumNumeratorValue: 40,
        initialShortCircuitNumerator: 100,
        initialVoteExtension: 2 days
    });

    _constructorParams = abi.encode(_params);
    _contractName = name;
    _address = payable(address(new FraxGovernorAlpha(_params)));
}

contract DeployFraxGovernorAlphaAndTimelock is BaseScript {
    function run()
        external
        broadcaster
        returns (address payable _address, bytes memory _constructorParams, string memory _contractName)
    {
        (address payable _addressTimelock, bytes memory _constructorParamsTimelock, ) = deployTimelockController(
            deployer
        );
        console.log("_constructorParamsTimelock:", string(abi.encode(_constructorParamsTimelock)));
        console.logBytes(_constructorParamsTimelock);
        console.log("_addressTimelock:", _addressTimelock);

        (_address, _constructorParams, _contractName) = deployFraxGovernorAlpha(
            Constants.VE_FXS,
            Constants.VE_FXS_VOTING_DELEGATION,
            _addressTimelock
        );

        TimelockController tc = TimelockController(_addressTimelock);

        tc.grantRole(tc.PROPOSER_ROLE(), _address);
        tc.grantRole(tc.EXECUTOR_ROLE(), _address);
        tc.grantRole(tc.CANCELLER_ROLE(), _address);
        tc.renounceRole(tc.TIMELOCK_ADMIN_ROLE(), deployer);
    }
}
