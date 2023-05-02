// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== FraxGovernor ===========================
// ====================================================================
// # FraxGovernor

// # Overview

// # Requirements

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch

import { FraxGovernorBase, ConstructorParams as FraxGovernorBaseParams } from "./FraxGovernorBase.sol";
import { IFraxGovernorAlpha } from "./interfaces/IFraxGovernorAlpha.sol";

struct ConstructorParams {
    address veFxs;
    address veFxsVotingDelegation;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 quorumNumeratorValue;
    uint256 initialShortCircuitNumerator;
}

contract FraxGovernorAlpha is FraxGovernorBase {
    constructor(
        ConstructorParams memory params
    )
        FraxGovernorBase(
            FraxGovernorBaseParams({
                veFxs: params.veFxs,
                veFxsVotingDelegation: params.veFxsVotingDelegation,
                _name: "FraxGovernorAlpha",
                initialVotingDelay: params.initialVotingDelay,
                initialVotingPeriod: params.initialVotingPeriod,
                initialProposalThreshold: params.initialProposalThreshold,
                quorumNumeratorValue: params.quorumNumeratorValue,
                initialShortCircuitNumerator: params.initialShortCircuitNumerator
            })
        )
    {}

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        _requireVeFxsProposalThreshold();
        return _propose(targets, values, calldatas, description);
    }

    function setVeFxsVotingDelegation(address _veFxsVotingDelegation) external onlyGovernance {
        _setVeFxsVotingDelegation(_veFxsVotingDelegation);
    }

    function updateShortCircuitNumerator(uint256 newShortCircuitNumerator) external onlyGovernance {
        _updateShortCircuitNumerator(newShortCircuitNumerator);
    }

    function state(uint256 proposalId) public view override returns (ProposalState) {
        ProposalCore storage proposal = proposals[proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert("Governor: unknown proposal id");
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        // Allow early execution when overwhelming majority
        if (_shortCircuitFor(proposalId)) {
            return ProposalState.Succeeded;
        } else if (_shortCircuitAgainst(proposalId)) {
            return ProposalState.Defeated;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        }

        if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Defeated;
        }
    }
}
