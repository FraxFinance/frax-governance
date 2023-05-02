// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { Constants } from "../script/Constants.sol";
import { FraxGovernorAlpha, ConstructorParams as FraxAlphaGovernorParams } from "../src/FraxGovernorAlpha.sol";
import {
    FraxGovernorOmega,
    ConstructorParams as FraxGovernorOmegaParams,
    SafeConfig
} from "../src/FraxGovernorOmega.sol";
import { FraxGuard } from "../src/FraxGuard.sol";
import { VeFxsVotingDelegation } from "../src/VeFxsVotingDelegation.sol";

function deployVeFxsVotingDelegation(
    address _veFxs
) returns (address payable _address, bytes memory _constructorParams, string memory _contractName) {
    _constructorParams = abi.encode(_veFxs);
    _contractName = "VeFxsVotingDelegation";
    _address = payable(address(new VeFxsVotingDelegation(_veFxs)));
}

function deployFraxGovernorAlpha(
    address _veFxs,
    address _veFxsVotingDelegation
) returns (address payable _address, bytes memory _constructorParams, string memory _contractName) {
    FraxAlphaGovernorParams memory _params = FraxAlphaGovernorParams({
        veFxs: _veFxs,
        veFxsVotingDelegation: _veFxsVotingDelegation,
        initialVotingDelay: Constants.INITIAL_VOTING_DELAY,
        initialVotingPeriod: 7 days,
        initialProposalThreshold: Constants.INITIAL_PROPOSAL_THRESHOLD,
        quorumNumeratorValue: 80,
        initialShortCircuitNumerator: Constants.INITIAL_SHORT_CIRCUIT_THRESHOLD
    });

    _constructorParams = abi.encode(_params);
    _contractName = "FraxGovernorAlpha";
    _address = payable(address(new FraxGovernorAlpha(_params)));
}

function deployFraxGovernorOmega(
    address _veFxs,
    address _veFxsVotingDelegation,
    SafeConfig[] memory _safeConfigs,
    address payable _fraxGovernorAlpha
) returns (address payable _address, bytes memory _constructorParams, string memory _contractName) {
    FraxGovernorOmegaParams memory _params = FraxGovernorOmegaParams({
        veFxs: _veFxs,
        veFxsVotingDelegation: _veFxsVotingDelegation,
        safeConfigs: _safeConfigs,
        _fraxGovernorAlpha: _fraxGovernorAlpha,
        initialVotingDelay: Constants.INITIAL_VOTING_DELAY,
        initialVotingPeriod: 2 days,
        initialProposalThreshold: Constants.INITIAL_PROPOSAL_THRESHOLD,
        quorumNumeratorValue: 4,
        initialShortCircuitNumerator: Constants.INITIAL_SHORT_CIRCUIT_THRESHOLD
    });

    _constructorParams = abi.encode(_params);
    _contractName = "FraxGovernorOmega";
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

        (_address, _constructorParams, _contractName) = deployFraxGovernorAlpha(Constants.VE_FXS, _addressVoting);
        console.log("_constructorParamsAlpha:", string(abi.encode(_constructorParams)));
        console.logBytes(_constructorParams);
        console.log("_addressAlpha:", _address);

        SafeConfig[] memory _safeConfigs = new SafeConfig[](2);
        //        _safeConfigs[0] = SafeConfig({safe: address(0), requiredSignatures: 3}); //TODO: prod values
        (
            address _addressOmega,
            bytes memory _constructorParamsOmega /* string memory _contractNameOmega */,

        ) = deployFraxGovernorOmega(Constants.VE_FXS, _addressVoting, _safeConfigs, _address);
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
