// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ========================= FraxGovernorAlpha ========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch

// Reviewers
// Drake Evans: https://github.com/DrakeEvans
// Dennis: https://github.com/denett
// Sam Kazemian: https://github.com/samkazemian

// ====================================================================

import { FraxGovernorBase, ConstructorParams as FraxGovernorBaseParams } from "./FraxGovernorBase.sol";
import { IFraxGovernorAlpha } from "./interfaces/IFraxGovernorAlpha.sol";

struct ConstructorParams {
    address veFxs;
    address veFxsVotingDelegation;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 quorumNumeratorValue;
    uint256 initialVotingDelayBlocks;
    uint256 initialShortCircuitNumerator;
}

/// @title FraxGovernorAlpha
/// @author Jon Walch (Frax Finance) https://github.com/jonwalch
/// @notice A Governance contract with intended use as a Gnosis Safe Module, giving it full control over the Safe(s).
contract FraxGovernorAlpha is FraxGovernorBase {
    /// @notice The ```constructor``` function is called on deployment
    /// @param params ConstructorParams struct
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
                initialVotingDelayBlocks: params.initialVotingDelayBlocks,
                initialShortCircuitNumerator: params.initialShortCircuitNumerator
            })
        )
    {}

    /// @notice The ```propose``` function is similar to OpenZeppelin's propose() with minor changes
    /// @dev Proposals that interact with a Gnosis Safe need to use GnosisSafe::execTransactionFromModule()
    /// @return proposalId Proposal ID
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256 proposalId) {
        _requireSenderAboveProposalThreshold();
        proposalId = _propose({ targets: targets, values: values, calldatas: calldatas, description: description });
    }

    /// @notice The ```setVotingDelayBlocks``` function is called by governance to change the amount of blocks before the voting snapshot
    /// @dev Only callable by governance through this contract
    /// @param newVotingDelayBlocks New voting delay in blocks
    function setVotingDelayBlocks(uint256 newVotingDelayBlocks) external onlyGovernance {
        _setVotingDelayBlocks(newVotingDelayBlocks);
    }

    /// @notice The ```setVeFxsVotingDelegation``` function is called by governance to change the voting weight IERC5805 contract
    /// @dev Only callable by governance through this contract
    /// @param veFxsVotingDelegation New IERC5805 veFxsVotingDelegation contract address
    function setVeFxsVotingDelegation(address veFxsVotingDelegation) external onlyGovernance {
        _setVeFxsVotingDelegation(veFxsVotingDelegation);
    }

    /// @notice The ```updateShortCircuitNumerator``` function is called by governance to change the short circuit numerator
    /// @dev Only callable by governance through this contract
    /// @param newShortCircuitNumerator Number expressed as x/100 (percentage)
    function updateShortCircuitNumerator(uint256 newShortCircuitNumerator) external onlyGovernance {
        _updateShortCircuitNumerator(newShortCircuitNumerator);
    }

    /// @notice The ```state``` function is similar to OpenZeppelin's propose() with minor changes
    /// @dev Changes include: support for early success or failure using short circuit
    /// @param proposalId Proposal ID
    /// @return proposalState ProposalState enum
    function state(uint256 proposalId) public view override returns (ProposalState proposalState) {
        ProposalCore storage $proposal = proposals[proposalId];

        if ($proposal.executed) {
            return ProposalState.Executed;
        }

        if ($proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert("Governor: unknown proposal id");
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint || $snapshotTimestampToSnapshotBlockNumber[snapshot] >= block.number) {
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
