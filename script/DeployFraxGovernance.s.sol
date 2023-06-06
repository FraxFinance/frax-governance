// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { Constants } from "../script/Constants.sol";
import { FraxGovernorAlpha, ConstructorParams as FraxAlphaGovernorParams } from "../src/FraxGovernorAlpha.sol";
import { FraxGovernorOmega, ConstructorParams as FraxGovernorOmegaParams } from "../src/FraxGovernorOmega.sol";
import { FraxGuard } from "../src/FraxGuard.sol";
import { VeFxsVotingDelegation } from "../src/VeFxsVotingDelegation.sol";

function deployVeFxsVotingDelegation(
    address _veFxs
) returns (address payable _address, bytes memory _constructorParams, string memory _contractName) {
    string memory version = "1";
    _constructorParams = abi.encode(_veFxs);
    _contractName = "VeFxsVotingDelegation";
    _address = payable(address(new VeFxsVotingDelegation(_veFxs, _contractName, version)));
}

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

function deployFraxGovernorOmega(
    address _veFxs,
    address _veFxsVotingDelegation,
    address[] memory _safeAllowlist,
    address payable _timelockController
) returns (address payable _address, bytes memory _constructorParams, string memory _contractName) {
    string memory name = "FraxGovernorOmega";
    uint256 votingDelay = 1 minutes;
    FraxGovernorOmegaParams memory _params = FraxGovernorOmegaParams({
        name: name,
        veFxs: _veFxs,
        veFxsVotingDelegation: _veFxsVotingDelegation,
        safeAllowlist: _safeAllowlist,
        timelockController: _timelockController,
        initialVotingDelay: votingDelay,
        initialVotingDelayBlocks: votingDelay / 12,
        initialVotingPeriod: 2 days,
        initialProposalThreshold: type(uint256).max,
        quorumNumeratorValue: 4,
        initialShortCircuitNumerator: 51
    });

    _constructorParams = abi.encode(_params);
    _contractName = name;
    _address = payable(address(new FraxGovernorOmega(_params)));
}

function deployFraxGuard(
    address _fraxGovernorOmega
) returns (address _address, bytes memory _constructorParams, string memory _contractName) {
    _constructorParams = abi.encode(_fraxGovernorOmega);
    _contractName = "FraxGuard";
    _address = address(new FraxGuard(_fraxGovernorOmega));
}

contract DeployFraxGovernance is BaseScript {
    function run()
        external
        broadcaster
        returns (address payable _address, bytes memory _constructorParams, string memory _contractName)
    {
        (address _addressVoting, bytes memory _constructorParamsVoting, ) = deployVeFxsVotingDelegation(
            Constants.VE_FXS
        );
        console.log("_constructorParamsVoting:", string(abi.encode(_constructorParamsVoting)));
        console.logBytes(_constructorParamsVoting);
        console.log("_addressVoting:", _addressVoting);

        (address payable _addressTimelock, bytes memory _constructorParamsTimelock, ) = deployTimelockController(
            deployer
        );
        console.log("_constructorParamsTimelock:", string(abi.encode(_constructorParamsTimelock)));
        console.logBytes(_constructorParamsTimelock);
        console.log("_addressTimelock:", _addressTimelock);

        (_address, _constructorParams, _contractName) = deployFraxGovernorAlpha(
            Constants.VE_FXS,
            _addressVoting,
            _addressTimelock
        );
        console.log("_constructorParamsAlpha:", string(abi.encode(_constructorParams)));
        console.logBytes(_constructorParams);
        console.log("_addressAlpha:", _address);

        TimelockController tc = TimelockController(_addressTimelock);

        tc.grantRole(tc.PROPOSER_ROLE(), _address);
        tc.grantRole(tc.EXECUTOR_ROLE(), _address);
        tc.grantRole(tc.CANCELLER_ROLE(), _address);
        tc.renounceRole(tc.TIMELOCK_ADMIN_ROLE(), deployer);

        address[] memory _safeAllowlist = new address[](2);
        //        _safeAllowlist[0] = address(0); //TODO: prod value
        (
            address _addressOmega,
            bytes memory _constructorParamsOmega /* string memory _contractNameOmega */,

        ) = deployFraxGovernorOmega(Constants.VE_FXS, _addressVoting, _safeAllowlist, _addressTimelock);
        console.log("_constructorParamsOmega:", string(abi.encode(_constructorParamsOmega)));
        console.logBytes(_constructorParamsOmega);
        console.log("_addressOmega:", _addressOmega);

        (
            address _addressGuard,
            bytes memory _constructorParamsGuard /* string memory _contractNameGuard */,

        ) = deployFraxGuard(_addressOmega);
        console.log("_constructorParamsGuard:", string(abi.encode(_constructorParamsGuard)));
        console.logBytes(_constructorParamsGuard);
        console.log("_addressGuard:", _addressGuard);
    }
}
