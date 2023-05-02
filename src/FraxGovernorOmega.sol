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
// This contract controls the FraxGovernanceOwner

// # Overview

// # Requirements

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch
// Jamie Turley: https://github.com/jyturley

import { FraxGovernorBase, ConstructorParams as FraxGovernorBaseParams } from "./FraxGovernorBase.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { ISafe, Enum } from "./interfaces/ISafe.sol";
import { IFraxGovernorOmega } from "./interfaces/IFraxGovernorOmega.sol";

struct SafeConfig {
    address safe;
    uint256 requiredSignatures;
}

struct ConstructorParams {
    address veFxs;
    address veFxsVotingDelegation;
    SafeConfig[] safeConfigs;
    address payable _fraxGovernorAlpha;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 quorumNumeratorValue;
    uint256 initialShortCircuitNumerator;
}

contract FraxGovernorOmega is FraxGovernorBase {
    address public immutable FRAX_GOVERNOR_ALPHA;

    //mapping(address safe => uint256 requiredSignatures) public gnosisSafeAllowlist;
    mapping(address => uint256) public $safeRequiredSignatures;
    //mapping(uint256 proposalId => bytes32 txHash) public vetoProposalIdToTxHash;
    mapping(uint256 => bytes32) public $optimisticProposalIdToTxHash;
    //mapping(address safe => mapping(uint256 safeNonce => bytes32 txHash)) public gnosisSafeToNonceToHash;
    mapping(address => mapping(uint256 => bytes32)) public $gnosisSafeToNonceToTxHash;

    event TransactionProposed(
        address indexed safe,
        uint256 nonce,
        bytes32 txHash,
        uint256 proposalId,
        address indexed proposer
    );
    event SafeConfigUpdate(address indexed safe, uint256 oldRequiredSignatures, uint256 newRequiredSignatures);

    /**
     * @dev This will construct new contract owners for the _teamSafe
     */
    constructor(
        ConstructorParams memory params
    )
        FraxGovernorBase(
            FraxGovernorBaseParams({
                veFxs: params.veFxs,
                veFxsVotingDelegation: params.veFxsVotingDelegation,
                _name: "FraxGovernorOmega",
                initialVotingDelay: params.initialVotingDelay,
                initialVotingPeriod: params.initialVotingPeriod,
                initialProposalThreshold: params.initialProposalThreshold,
                quorumNumeratorValue: params.quorumNumeratorValue,
                initialShortCircuitNumerator: params.initialShortCircuitNumerator
            })
        )
    {
        FRAX_GOVERNOR_ALPHA = params._fraxGovernorAlpha;

        for (uint256 i = 0; i < params.safeConfigs.length; ++i) {
            SafeConfig memory config = params.safeConfigs[i];
            $safeRequiredSignatures[config.safe] = config.requiredSignatures;
            emit SafeConfigUpdate(config.safe, 0, config.requiredSignatures);
        }
    }

    function _requireOnlyGovernorAlpha() internal view {
        if (msg.sender != FRAX_GOVERNOR_ALPHA) revert IFraxGovernorOmega.NotGovernorAlpha();
    }

    function _requireAllowlist(address safe) internal view {
        if ($safeRequiredSignatures[safe] == 0) revert Unauthorized();
    }

    // Disallow v == 0 and v == 1 cases of safe.checkNSignatures(). This ensures that the signatures passed in are from
    // EOAs and don't allow the implicit signing from Omega with msg.sender == currentOwner.
    function _requireEoaSignatures(address safe, bytes memory signatures) internal view {
        uint8 v;
        uint256 i;

        for (i = 0; i < $safeRequiredSignatures[safe]; ++i) {
            // Taken from Gnosis Safe SignatureDecoder
            assembly {
                let signaturePos := mul(0x41, i)
                v := and(mload(add(signatures, add(signaturePos, 0x41))), 0xff)
            }
            if (v < 2) {
                revert IFraxGovernorOmega.WrongSafeSignatureType();
            }
        }
    }

    function _optimisticProposalArgs(
        address safe,
        bytes32 txHash
    ) internal pure returns (address[] memory, uint256[] memory, bytes[] memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = safe;
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(ISafe.approveHash.selector, txHash);
        return (targets, values, calldatas);
    }

    // Exists solely to avoid stack too deep errors in addTransaction()
    function _safeGetTransactionHash(
        ISafe safe,
        IFraxGovernorOmega.TxHashArgs memory args
    ) internal view returns (bytes32) {
        return
            safe.getTransactionHash({
                to: args.to,
                value: args.value,
                data: args.data,
                operation: args.operation,
                safeTxGas: args.safeTxGas,
                baseGas: args.baseGas,
                gasPrice: args.gasPrice,
                gasToken: args.gasToken,
                refundReceiver: args.refundReceiver,
                _nonce: args._nonce
            });
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        _requireVeFxsProposalThreshold();

        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            // Disallow allowlisted safes because Omega would be able to call approveHash outside of the
            // addTransaction() / execute() / rejectTransaction() flow
            if ($safeRequiredSignatures[target] != 0) {
                revert IFraxGovernorOmega.DisallowedTarget(target);
            }
        }

        return _propose(targets, values, calldatas, description);
    }

    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public override returns (uint256) {
        if ($optimisticProposalIdToTxHash[hashProposal(targets, values, calldatas, descriptionHash)] != 0) {
            revert IFraxGovernorOmega.CannotCancelOptimisticTransaction();
        }

        return super.cancel(targets, values, calldatas, descriptionHash);
    }

    function batchAddTransaction(
        address[] calldata teamSafes,
        IFraxGovernorOmega.TxHashArgs[] calldata args,
        bytes[] calldata signatures
    ) external returns (uint256[] memory) {
        if (teamSafes.length != args.length || teamSafes.length != signatures.length) {
            revert IFraxGovernorOmega.BadBatchArgs();
        }

        uint256[] memory optimisticProposalIds = new uint256[](teamSafes.length);

        for (uint256 i = 0; i < teamSafes.length; ++i) {
            optimisticProposalIds[i] = addTransaction({
                teamSafe: teamSafes[i],
                args: args[i],
                signatures: signatures[i]
            });
        }
        return optimisticProposalIds;
    }

    function addTransaction(
        address teamSafe,
        IFraxGovernorOmega.TxHashArgs calldata args,
        bytes calldata signatures
    ) public returns (uint256 optimisticProposalId) {
        _requireEoaSignatures({ safe: teamSafe, signatures: signatures });
        // This check stops EOA Safe owners from pushing txs through that skip the more stringent FraxGovernorAlpha
        // procedures. It disallows Omega from calling approveHash outside of the
        // addTransaction() / execute() / rejectTransaction() flow
        if (args.to == teamSafe) {
            revert IFraxGovernorOmega.DisallowedTarget(args.to);
        }
        _requireAllowlist(teamSafe);
        if ($gnosisSafeToNonceToTxHash[teamSafe][args._nonce] != 0) revert IFraxGovernorOmega.NonceReserved();
        ISafe safe = ISafe(teamSafe);
        if (args._nonce < safe.nonce()) revert IFraxGovernorOmega.WrongNonce();

        bytes32 txHash = _safeGetTransactionHash({ safe: safe, args: args });

        safe.checkNSignatures({
            dataHash: txHash,
            data: args.data,
            signatures: signatures,
            requiredSignatures: $safeRequiredSignatures[teamSafe]
        });

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _optimisticProposalArgs(
            teamSafe,
            txHash
        );

        optimisticProposalId = _propose(targets, values, calldatas, "");

        $optimisticProposalIdToTxHash[optimisticProposalId] = txHash;
        $gnosisSafeToNonceToTxHash[teamSafe][args._nonce] = txHash;

        emit TransactionProposed({
            safe: teamSafe,
            nonce: args._nonce,
            txHash: txHash,
            proposalId: optimisticProposalId,
            proposer: msg.sender
        });
    }

    function rejectTransaction(address teamSafe, uint256 nonce) external {
        bytes32 originalTxHash = $gnosisSafeToNonceToTxHash[teamSafe][nonce];

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _optimisticProposalArgs(
            teamSafe,
            originalTxHash
        );
        if (state(hashProposal(targets, values, calldatas, keccak256(bytes("")))) != ProposalState.Defeated) {
            revert IFraxGovernorOmega.WrongProposalState();
        }

        ISafe safe = ISafe(teamSafe);
        bytes32 rejectTxHash = _safeGetTransactionHash({
            safe: safe,
            args: IFraxGovernorOmega.TxHashArgs({
                to: teamSafe,
                value: 0,
                data: "",
                operation: Enum.Operation.Call,
                safeTxGas: 0,
                baseGas: 0,
                gasPrice: 0,
                gasToken: address(0),
                refundReceiver: payable(address(0)),
                _nonce: nonce
            })
        });

        if (safe.approvedHashes({ signer: address(this), txHash: rejectTxHash }) == 1) {
            revert IFraxGovernorOmega.TransactionAlreadyApproved(rejectTxHash);
        }

        // Omega approves 0 eth transfer
        safe.approveHash(rejectTxHash);
    }

    /**
     * @notice Immediately negate a gnosis tx and veto proposal with a 0 eth transfer
     * @notice Cannot be applied to swap owner proposals or governance parameter proposals.
     * @notice An EOA owner will go into the safe UI, use the reject transaction flow, and get 3 EOA owners to sign
     * @param signatures 3 valid signatures from 3/5 EOA owners of the multisig
     */
    function abortTransaction(address teamSafe, bytes calldata signatures) external {
        _requireEoaSignatures({ safe: teamSafe, signatures: signatures });
        _requireAllowlist(teamSafe);

        ISafe safe = ISafe(teamSafe);
        uint256 nonce = safe.nonce();

        bytes32 rejectTxHash = safe.getTransactionHash({
            to: teamSafe,
            value: 0,
            data: "",
            operation: Enum.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            _nonce: nonce
        });

        // Check validity of provided 3 signatures for generated txHash
        safe.checkNSignatures({
            dataHash: rejectTxHash,
            data: "",
            signatures: signatures,
            requiredSignatures: $safeRequiredSignatures[teamSafe]
        });

        bytes32 originalTxHash = $gnosisSafeToNonceToTxHash[teamSafe][nonce];
        uint256 abortedProposalId;

        // If safe/nonce tuple already had addTransaction() called for it
        if (originalTxHash != 0) {
            (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _optimisticProposalArgs(
                teamSafe,
                originalTxHash
            );

            abortedProposalId = hashProposal(targets, values, calldatas, keccak256(bytes("")));
            ProposalState proposalState = state(abortedProposalId);

            // Cancel voting for proposal
            if (proposalState == ProposalState.Pending || proposalState == ProposalState.Active) {
                proposals[abortedProposalId].canceled = true;
                emit ProposalCanceled(abortedProposalId);
            }
        }

        // Omega approves 0 eth transfer
        safe.approveHash(rejectTxHash);
    }

    function setVotingDelay(uint256 newVotingDelay) public override {
        _requireOnlyGovernorAlpha();
        _setVotingDelay(newVotingDelay);
    }

    function setVotingPeriod(uint256 newVotingPeriod) public override {
        _requireOnlyGovernorAlpha();
        _setVotingPeriod(newVotingPeriod);
    }

    function setProposalThreshold(uint256 newProposalThreshold) public override {
        _requireOnlyGovernorAlpha();
        _setProposalThreshold(newProposalThreshold);
    }

    function updateQuorumNumerator(uint256 newQuorumNumerator) external override {
        _requireOnlyGovernorAlpha();
        _updateQuorumNumerator(newQuorumNumerator);
    }

    function setVeFxsVotingDelegation(address _veFxsVotingDelegation) external {
        _requireOnlyGovernorAlpha();
        _setVeFxsVotingDelegation(_veFxsVotingDelegation);
    }

    function updateShortCircuitNumerator(uint256 newShortCircuitNumerator) external {
        _requireOnlyGovernorAlpha();
        _updateShortCircuitNumerator(newShortCircuitNumerator);
    }

    // safes are expected to be properly configured before calling this function. At time of writing,
    // they should have the FraxGuard set, have FraxGovernorOmega set as a signer and set FraxGovernor Alpha as Module
    // Can use to add or remove safes. See TestFraxGovernorUpgrade.t.sol for upgrade path.
    function updateSafes(SafeConfig[] calldata safeConfigs) external {
        _requireOnlyGovernorAlpha();

        for (uint256 i = 0; i < safeConfigs.length; ++i) {
            SafeConfig calldata config = safeConfigs[i];
            uint256 previousSignatures = $safeRequiredSignatures[config.safe];
            $safeRequiredSignatures[config.safe] = config.requiredSignatures;
            emit SafeConfigUpdate(config.safe, previousSignatures, config.requiredSignatures);
        }
    }

    function _optimisticVoteDefeated(uint256 proposalId) internal view returns (bool) {
        (uint256 againstVoteWeight, uint256 forVoteWeight, ) = proposalVotes(proposalId);
        if (againstVoteWeight == 0 && forVoteWeight == 0) {
            return false;
        } else {
            return forVoteWeight <= againstVoteWeight;
        }
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

        // Optimistic proposal with addTransaction()
        if ($optimisticProposalIdToTxHash[proposalId] != 0) {
            if (_quorumReached(proposalId) && _optimisticVoteDefeated(proposalId)) {
                return ProposalState.Defeated;
            } else {
                return ProposalState.Succeeded;
            }

            // Regular proposal with propose()
        } else {
            if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
                return ProposalState.Succeeded;
            } else {
                return ProposalState.Defeated;
            }
        }
    }
}
