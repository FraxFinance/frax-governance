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
import { Governor, IGovernor } from "./governor/Governor.sol";
import { GovernorPreventLateQuorum } from "./governor/GovernorPreventLateQuorum.sol";
import { GovernorTimelockControl, TimelockController } from "./governor/GovernorTimelockControl.sol";

struct ConstructorParams {
    string name;
    address veFxs;
    address veFxsVotingDelegation;
    address payable timelockController;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 quorumNumeratorValue;
    uint256 initialVotingDelayBlocks;
    uint256 initialShortCircuitNumerator;
    uint64 initialVoteExtension;
}

/// @title FraxGovernorAlpha
/// @author Jon Walch (Frax Finance) https://github.com/jonwalch
/// @notice A Governance contract with its TimelockController set as a Gnosis Safe Module, giving it full control over the Safe(s).
contract FraxGovernorAlpha is FraxGovernorBase, GovernorTimelockControl, GovernorPreventLateQuorum {
    /// @notice The ```constructor``` function is called on deployment
    /// @param params ConstructorParams struct
    constructor(
        ConstructorParams memory params
    )
        FraxGovernorBase(
            FraxGovernorBaseParams({
                veFxs: params.veFxs,
                veFxsVotingDelegation: params.veFxsVotingDelegation,
                _name: params.name,
                initialVotingDelay: params.initialVotingDelay,
                initialVotingPeriod: params.initialVotingPeriod,
                initialProposalThreshold: params.initialProposalThreshold,
                quorumNumeratorValue: params.quorumNumeratorValue,
                initialVotingDelayBlocks: params.initialVotingDelayBlocks,
                initialShortCircuitNumerator: params.initialShortCircuitNumerator
            })
        )
        GovernorPreventLateQuorum(params.initialVoteExtension)
        GovernorTimelockControl(TimelockController(params.timelockController))
    {}

    /// @notice The ```propose``` function is similar to OpenZeppelin's propose() with minor changes
    /// @dev Proposals that interact with a Gnosis Safe need to use GnosisSafe::execTransactionFromModule()
    /// @return proposalId Proposal ID
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, IGovernor) returns (uint256 proposalId) {
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

    /// @notice The ```state``` function is largely copied from GovernorTimelockControl
    /// @dev Changes include: support for early success or failure using short circuit
    /// @param proposalId Proposal ID
    /// @return proposalState ProposalState enum
    function state(
        uint256 proposalId
    ) public view override(Governor, GovernorTimelockControl) returns (ProposalState proposalState) {
        ProposalState currentState = _state(proposalId);

        if (currentState != ProposalState.Succeeded) {
            return currentState;
        }

        // core tracks execution, so we just have to check if successful proposal have been queued.
        bytes32 queueid = $timelockIds[proposalId];
        if (queueid == bytes32(0)) {
            return currentState;
        } else if ($timelock.isOperationDone(queueid)) {
            return ProposalState.Executed; // never hit because execution is marked in _state on the proposal
        } else if ($timelock.isOperationPending(queueid)) {
            return ProposalState.Queued;
        } else {
            return ProposalState.Canceled; // never hit because cant cancel after voting delay
        }
    }

    /// @notice The ```_state``` function emulates OpenZeppelin Governor's state function with a small change
    /// @dev The only change is support for early
    /// @param proposalId Proposal ID
    /// @return proposalState Proposal state
    function _state(uint256 proposalId) private view returns (ProposalState proposalState) {
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

    /// @notice The ```_propose``` function is similar to OpenZeppelin's propose() with minor changes.
    /// @dev Changes include: Removal of proposal threshold check, ProposalCore struct packing, and setting $snapshotToTotalVeFxsSupply
    /// @return proposalId Proposal ID
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256 proposalId) {
        proposalId = hashProposal({
            targets: targets,
            values: values,
            calldatas: calldatas,
            descriptionHash: keccak256(bytes(description))
        });

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");
        require(proposals[proposalId].voteStart == 0, "Governor: proposal already exists");

        address proposer = msg.sender;
        uint256 snapshot = clock() + votingDelay();
        uint256 deadline = snapshot + votingPeriod();

        proposals[proposalId] = ProposalCore({
            proposer: proposer,
            voteStart: uint40(snapshot),
            voteEnd: uint40(deadline),
            executed: false,
            canceled: false
        });

        // Save the block number of the snapshot, so it can be later used to fetch the total outstanding supply
        // of veFXS. We did this so we can still support quorum(timestamp), without breaking the OZ standard.
        // The underlying issue is that VE_FXS.totalSupply(timestamp) doesn't work for historical values, so we must
        // use VE_FXS.totalSupply(), or VE_FXS.totalSupplyAt(blockNumber).
        $snapshotTimestampToSnapshotBlockNumber[snapshot] = block.number + $votingDelayBlocks;

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description
        );
    }

    /// Boilerplate overrides

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(Governor, GovernorTimelockControl) returns (bool) {
        return GovernorTimelockControl.supportsInterface(interfaceId);
    }

    /**
     * @dev Overridden execute function that run the already queued proposal through the timelock.
     */
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        GovernorTimelockControl._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Overridden version of the {Governor-_cancel} function to cancel the timelocked proposal if it as already
     * been queued.
     */
    // This function can reenter through the external call to the timelock, but we assume the timelock is trusted and
    // well behaved (according to TimelockController) and this will not happen.
    // slither-disable-next-line reentrancy-no-eth
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return
            GovernorTimelockControl._cancel({
                targets: targets,
                values: values,
                calldatas: calldatas,
                descriptionHash: descriptionHash
            });
    }

    /**
     * @dev Address through which the governor executes action. In this case, the timelock.
     */
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return GovernorTimelockControl._executor();
    }

    /**
     * @dev Returns the proposal deadline, which may have been extended beyond that set at proposal creation, if the
     * proposal reached quorum late in the voting period. See {Governor-proposalDeadline}.
     */
    function proposalDeadline(
        uint256 proposalId
    ) public view override(IGovernor, Governor, GovernorPreventLateQuorum) returns (uint256) {
        return GovernorPreventLateQuorum.proposalDeadline(proposalId);
    }

    /**
     * @dev Casts a vote and detects if it caused quorum to be reached, potentially extending the voting period. See
     * {Governor-_castVote}.
     *
     * May emit a {ProposalExtended} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal override(Governor, GovernorPreventLateQuorum) returns (uint256) {
        return
            GovernorPreventLateQuorum._castVote({
                proposalId: proposalId,
                account: account,
                support: support,
                reason: reason,
                params: params
            });
    }

    /**
     * @notice Cast a vote with a reason and additional encoded parameters using
     * the user's cryptographic signature.
     *
     * Emits a {VoteCast} or {VoteCastWithParams} event depending on the length
     * of params.
     *
     * @dev If casting a fractional vote via `params`, the voter's current nonce
     * must be appended to the `params` as the last 16 bytes and included in the
     * signature. I.e., the params used when constructing the signature would be:
     *
     *   abi.encodePacked(againstVotes, forVotes, abstainVotes, nonce)
     *
     * See {fractionalVoteNonce} and {_castVote} for more information.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override(IGovernor, Governor, FraxGovernorBase) returns (uint256) {
        return
            FraxGovernorBase.castVoteWithReasonAndParamsBySig({
                proposalId: proposalId,
                support: support,
                reason: reason,
                params: params,
                v: v,
                r: r,
                s: s
            });
    }

    /**
     * @dev See {Governor-proposalThreshold}.
     */
    function proposalThreshold() public view override(Governor, FraxGovernorBase) returns (uint256) {
        return FraxGovernorBase.proposalThreshold();
    }
}
