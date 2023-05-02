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
// ========================= FraxGovernorBase =========================
// ====================================================================
// Inherited by FraxGovernor
// veFXS holders can delegate votes to other addresses to vote on their behalf

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch

import { Checkpoints } from "@openzeppelin/contracts/utils/Checkpoints.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { GovernorCountingFractional, SafeCast } from "./GovernorCountingFractional.sol";
import { ISafe } from "./interfaces/ISafe.sol";
import { IVeFxs } from "./interfaces/IVeFxs.sol";
import { IERC5805 } from "@openzeppelin/contracts/interfaces/IERC5805.sol";

struct ConstructorParams {
    address veFxs;
    address veFxsVotingDelegation;
    string _name;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 quorumNumeratorValue;
    uint256 initialShortCircuitNumerator;
}

abstract contract FraxGovernorBase is GovernorCountingFractional {
    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    /// Address of the veFXS contract
    IVeFxs public immutable VE_FXS;

    Checkpoints.Trace224 private _$shortCircuitNumeratorHistory;

    //    mapping(uint256 snapshot => uint256 totalVeFxsSupply) public $snapshotToTotalVeFxsSupply;
    mapping(uint256 => uint256) public $snapshotToTotalVeFxsSupply;

    event VeFxsVotingDelegationSet(address oldVotingDelegation, address newVotingDelegation);
    event ShortCircuitNumeratorUpdated(uint256 oldShortCircuitThreshold, uint256 newShortCircuitThreshold);

    constructor(
        ConstructorParams memory params
    )
        GovernorCountingFractional(
            params.veFxsVotingDelegation,
            params._name,
            params.quorumNumeratorValue,
            params.initialVotingDelay,
            params.initialVotingPeriod,
            params.initialProposalThreshold
        )
    {
        VE_FXS = IVeFxs(params.veFxs);
        _updateShortCircuitNumerator(params.initialShortCircuitNumerator);

        emit VeFxsVotingDelegationSet({
            oldVotingDelegation: address(0),
            newVotingDelegation: params.veFxsVotingDelegation
        });
    }

    function _requireVeFxsProposalThreshold() internal view {
        if (_getVotes(_msgSender(), block.timestamp - 1, "") < proposalThreshold()) {
            revert BelowVeFxsProposalThreshold();
        }
    }

    // only change is removing require statement for proposal threshold, we do that in inhering contracts
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256) {
        address proposer = _msgSender();
        uint256 currentTimepoint = clock();

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");
        require(proposals[proposalId].voteStart == 0, "Governor: proposal already exists");

        uint256 snapshot = currentTimepoint + votingDelay();
        uint256 deadline = snapshot + votingPeriod();

        proposals[proposalId] = ProposalCore({
            proposer: proposer,
            voteStart: SafeCast.toUint40(snapshot),
            voteEnd: SafeCast.toUint40(deadline),
            executed: false,
            canceled: false
        });

        // Takes the totalSupply at time of proposal creation, instead of at voting start. We did this so we can
        // still support quorum(timestamp), without breaking the OZ standard. The underlying issue is that
        // VE_FXS.totalSupply(timestamp) doesn't work for historical values, so we must use VE_FXS.totalSupply().
        $snapshotToTotalVeFxsSupply[snapshot] = VE_FXS.totalSupply();

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

        return proposalId;
    }

    function _setVeFxsVotingDelegation(address _veFxsVotingDelegation) internal {
        address oldVeFxsVotingDelegation = address(token);
        token = IERC5805(_veFxsVotingDelegation);
        emit VeFxsVotingDelegationSet({
            oldVotingDelegation: oldVeFxsVotingDelegation,
            newVotingDelegation: _veFxsVotingDelegation
        });
    }

    function _quorumReached(uint256 proposalId) internal view override returns (bool) {
        (uint256 againstVoteWeight, uint256 forVoteWeight, uint256 abstainVoteWeight) = proposalVotes(proposalId);
        uint256 larger = againstVoteWeight > forVoteWeight ? againstVoteWeight : forVoteWeight;

        return quorum(proposalSnapshot(proposalId)) <= larger + abstainVoteWeight;
    }

    function _shortCircuitFor(uint256 proposalId) internal view returns (bool) {
        (, uint256 forVoteWeight, ) = proposalVotes(proposalId);

        return forVoteWeight > shortCircuitThreshold(proposalSnapshot(proposalId));
    }

    function _shortCircuitAgainst(uint256 proposalId) internal view returns (bool) {
        (uint256 againstVoteWeight, , ) = proposalVotes(proposalId);

        return againstVoteWeight > shortCircuitThreshold(proposalSnapshot(proposalId));
    }

    function COUNTING_MODE() public pure override returns (string memory) {
        return "support=bravo&quorum=against,abstain&quorum=for,abstain&params=fractional";
    }

    // Only supports historical quorum values for proposals that actually exist.
    function quorum(uint256 timepoint) public view override returns (uint256) {
        uint256 totalSupply = $snapshotToTotalVeFxsSupply[timepoint];
        if (totalSupply == 0) revert InvalidTimepoint();

        return (totalSupply * quorumNumerator(timepoint)) / quorumDenominator();
    }

    // Only supports historical quorum values for proposals that actually exist.
    function shortCircuitThreshold(uint256 timepoint) public view returns (uint256) {
        uint256 totalSupply = $snapshotToTotalVeFxsSupply[timepoint];
        if (totalSupply == 0) revert InvalidTimepoint();

        return (totalSupply * shortCircuitNumerator(timepoint)) / quorumDenominator();
    }

    function shortCircuitNumerator() public view returns (uint256) {
        return _$shortCircuitNumeratorHistory.latest();
    }

    function shortCircuitNumerator(uint256 timepoint) public view returns (uint256) {
        // If history is empty, fallback to old storage
        uint256 length = _$shortCircuitNumeratorHistory._checkpoints.length;

        // Optimistic search, check the latest checkpoint
        Checkpoints.Checkpoint224 memory latest = _$shortCircuitNumeratorHistory._checkpoints[length - 1];
        if (latest._key <= timepoint) {
            return latest._value;
        }

        // Otherwise, do the binary search
        return _$shortCircuitNumeratorHistory.upperLookupRecent(SafeCast.toUint32(timepoint));
    }

    function _updateShortCircuitNumerator(uint256 newShortCircuitNumerator) internal {
        if (newShortCircuitNumerator > quorumDenominator()) {
            revert ShortCircuitNumeratorOverQuorumDenominator();
        }

        uint256 oldShortCircuitNumerator = shortCircuitNumerator();

        // Set new quorum for future proposals
        _$shortCircuitNumeratorHistory.push(clock().toUint32(), newShortCircuitNumerator.toUint224());

        emit ShortCircuitNumeratorUpdated({
            oldShortCircuitThreshold: oldShortCircuitNumerator,
            newShortCircuitThreshold: newShortCircuitNumerator
        });
    }

    error ShortCircuitNumeratorOverQuorumDenominator();
    error BelowVeFxsProposalThreshold();
    error Unauthorized();
    error InvalidTimepoint();
}
