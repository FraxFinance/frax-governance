// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { Constants } from "../script/Constants.sol";
import { FraxGovernorOmega, ConstructorParams as FraxGovernorOmegaParams } from "../src/FraxGovernorOmega.sol";

function deployFraxGovernorOmega(
    address _veFxs,
    address _veFxsVotingDelegation,
    address[] memory _safeAllowlist,
    address[] memory _delegateCallAllowlist,
    address payable _timelockController
) returns (address payable _address, bytes memory _constructorParams, string memory _contractName) {
    string memory name = "FraxGovernorOmega";
    uint256 votingDelay = 1 minutes;
    FraxGovernorOmegaParams memory _params = FraxGovernorOmegaParams({
        name: name,
        veFxs: _veFxs,
        veFxsVotingDelegation: _veFxsVotingDelegation,
        safeAllowlist: _safeAllowlist,
        delegateCallAllowlist: _delegateCallAllowlist,
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

contract DeployFraxGovernorOmega is BaseScript {
    function run()
        external
        broadcaster
        returns (address payable _address, bytes memory _constructorParams, string memory _contractName)
    {
        address[] memory _safeAllowlist = new address[](10);
        _safeAllowlist[0] = Constants.FRAX_COMMUNITY_MULTISIG;
        _safeAllowlist[1] = Constants.FRAX_TEAM_MULTISIG;
        _safeAllowlist[2] = Constants.FRAX_INVESTORS_MULTISIG;
        _safeAllowlist[3] = Constants.FRAX_TREASURY_MULTISIG;
        _safeAllowlist[4] = Constants.FRAX_ADVISORS_MULTISIG;
        _safeAllowlist[5] = Constants.FRAX_COMPTROLLERS_MULTISIG;
        _safeAllowlist[6] = Constants.FRAX_BUSINESS_DEVELOPMENT_MULTISIG;
        _safeAllowlist[7] = Constants.FRAX_CODE_DEVELOPMENT_MULTISIG;
        _safeAllowlist[8] = Constants.FRAX_FRAXLEND_COMPTROLLER_MULTISIG;
        _safeAllowlist[9] = Constants.FRAX_FRXETH_MULTISIG;

        address[] memory _delegateCallAllowlist = new address[](2);
        _delegateCallAllowlist[0] = Constants.SIGN_MESSAGE_LIB;
        _delegateCallAllowlist[1] = Constants.MULTI_SEND_CALL_ONLY;

        (_address, _constructorParams, _contractName) = deployFraxGovernorOmega(
            Constants.VE_FXS,
            Constants.VE_FXS_VOTING_DELEGATION,
            _safeAllowlist,
            _delegateCallAllowlist,
            payable(Constants.FRAX_GOVERNOR_ALPHA_TIMELOCK)
        );
    }
}
