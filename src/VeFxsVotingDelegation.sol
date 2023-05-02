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
// ======================= VeFxsVotingDelegation =======================
// ====================================================================
// # VeFxsVotingDelegation

// # Overview

// # Requirements

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch
// Jamie Turley: https://github.com/jyturley

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC5805 } from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import { IVeFxs } from "./interfaces/IVeFxs.sol";
import { IVeFxsVotingDelegation } from "./interfaces/IVeFxsVotingDelegation.sol";

contract VeFxsVotingDelegation is EIP712, IERC5805 {
    using SafeCast for uint256;

    uint256 public constant WEEK = 7 days;
    uint256 public constant VOTE_WEIGHT_MULTIPLIER = 3;

    // keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)")
    bytes32 public constant DELEGATION_TYPEHASH = 0xe48329057bfd03d55e49b547132e39cffd9c1820ad7b9d4c5307691425d15adf;

    IVeFxs public immutable VE_FXS;

    mapping(address => uint256) public $nonces;
    //mapping(address delegator => Delegation delegate) public delegations;
    mapping(address => IVeFxsVotingDelegation.Delegation) public $delegations;
    //mapping(address delegate => DelegateCheckpoint[]) public checkpoints;
    mapping(address => IVeFxsVotingDelegation.DelegateCheckpoint[]) public $checkpoints;
    //mapping(address delegate => mapping(uint256 week => Expiration)) public expirations;
    mapping(address => mapping(uint256 => IVeFxsVotingDelegation.Expiration)) public $expirations;

    constructor(address veFxs) EIP712("VeFxsVotingDelegation", "1") {
        VE_FXS = IVeFxs(veFxs);
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function getCheckpoint(
        address account,
        uint32 pos
    ) external view returns (IVeFxsVotingDelegation.DelegateCheckpoint memory) {
        return $checkpoints[account][pos];
    }

    function _calculateDelegatedWeight(address account, uint256 timestamp) internal view returns (uint256) {
        // Check if account has any delegations
        IVeFxsVotingDelegation.DelegateCheckpoint memory checkpoint = _checkpointLookup({
            _checkpoints: $checkpoints[account],
            timestamp: timestamp
        });
        if (checkpoint.timestamp == 0) {
            return 0;
        }

        // It's possible that some delegated veFXS has expired.
        // Add up all expirations during this time period, week by week.
        (uint256 totalExpiredBias, uint256 totalExpiredSlope, uint256 totalExpiredFxs) = _calculateExpirations({
            account: account,
            start: checkpoint.timestamp,
            end: timestamp
        });

        uint256 expirationAdjustedBias = checkpoint.normalizedBias - totalExpiredBias;
        uint256 expirationAdjustedSlope = checkpoint.normalizedSlope - totalExpiredSlope;
        uint256 expirationAdjustedFxs = checkpoint.totalFxs - totalExpiredFxs;

        uint256 voteDecay = expirationAdjustedSlope * timestamp;
        uint256 biasAtTimestamp = (expirationAdjustedBias > voteDecay) ? expirationAdjustedBias - voteDecay : 0;

        return expirationAdjustedFxs + (VOTE_WEIGHT_MULTIPLIER * biasAtTimestamp);
    }

    function _calculateWeight(address account, uint256 timestamp) internal view returns (uint256) {
        if (VE_FXS.locked(account).end <= timestamp) return 0;

        IVeFxsVotingDelegation.Delegation memory delegation = $delegations[account];

        if (
            // undelegated but old delegation still in effect until next epoch
            (delegation.delegate == address(0) && timestamp >= delegation.timestamp) ||
            // delegated but delegation not in effect until next epoch
            (delegation.previousDelegate == address(0) &&
                delegation.delegate != address(0) &&
                timestamp < delegation.timestamp)
        ) {
            try VE_FXS.balanceOf({ addr: account, _t: timestamp }) returns (uint256 _balance) {
                return _balance;
            } catch {}
        }
        return 0;
    }

    function calculateExpirations(
        address account
    ) public view returns (IVeFxsVotingDelegation.DelegateCheckpoint memory) {
        IVeFxsVotingDelegation.DelegateCheckpoint[] storage userDelegationCheckpoints = $checkpoints[account];
        uint256 checkpointTimestamp = ((block.timestamp / 1 days) * 1 days) + 1 days;
        uint256 checkpointsLength = userDelegationCheckpoints.length;

        // Nothing to expire if no one delegated to you
        if (checkpointsLength == 0) return IVeFxsVotingDelegation.DelegateCheckpoint(0, 0, 0, 0);

        IVeFxsVotingDelegation.DelegateCheckpoint memory lastCheckpoint = userDelegationCheckpoints[
            checkpointsLength - 1
        ];

        // Nothing expired because the most recent checkpoint is already written
        if (lastCheckpoint.timestamp == checkpointTimestamp) {
            return IVeFxsVotingDelegation.DelegateCheckpoint(0, 0, 0, 0);
        }

        (uint256 totalExpiredBias, uint256 totalExpiredSlope, uint256 totalExpiredFxs) = _calculateExpirations(
            account,
            lastCheckpoint.timestamp,
            checkpointTimestamp
        );

        // All will be 0 if no expirations, only need to check one of them
        if (totalExpiredFxs == 0) return IVeFxsVotingDelegation.DelegateCheckpoint(0, 0, 0, 0);

        return
            IVeFxsVotingDelegation.DelegateCheckpoint({
                timestamp: SafeCast.toUint128(checkpointTimestamp),
                normalizedBias: SafeCast.toUint128(lastCheckpoint.normalizedBias - totalExpiredBias),
                normalizedSlope: SafeCast.toUint128(lastCheckpoint.normalizedSlope - totalExpiredSlope),
                totalFxs: SafeCast.toUint128(lastCheckpoint.totalFxs - totalExpiredFxs)
            });
    }

    function writeNewCheckpointForExpirations(address account) external {
        IVeFxsVotingDelegation.DelegateCheckpoint memory _newCheckpoint = calculateExpirations(account);

        if (_newCheckpoint.timestamp == 0) revert IVeFxsVotingDelegation.NoExpirations();

        $checkpoints[account].push(_newCheckpoint);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @notice Ask veFXS for a given user's voting power at a certain timestamp
     * @param account Voter address
     * @param timestamp To ensure voter has sufficient power at the time of proposal
     */
    function _getVoteWeight(address account, uint256 timestamp) internal view returns (uint256) {
        return
            _calculateWeight({ account: account, timestamp: timestamp }) +
            _calculateDelegatedWeight({ account: account, timestamp: timestamp });
    }

    function getVotes(address account, uint256 timepoint) external view returns (uint256) {
        return _getVoteWeight(account, timepoint);
    }

    function getVotes(address account) external view returns (uint256) {
        return _getVoteWeight(account, block.timestamp);
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        if (timepoint >= block.timestamp) revert IVeFxsVotingDelegation.TimestampInFuture();

        return _getVoteWeight(account, timepoint);
    }

    // Must use block.number instead of timestamp because VE_FXS.totalSupply(timestamp) doesn't work for historical values.
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        if (blockNumber >= block.number) revert IVeFxsVotingDelegation.BlockNumberInFuture();

        // Our total voting weight isn't the same as VE_FXS.totalSupplyAt(blockNumber) because
        // we expire all voting weight when the lock ends, which also may not be accounted for yet.
        // This is close enough.
        return VE_FXS.totalSupplyAt(blockNumber);
    }

    function delegates(address account) external view returns (address) {
        return $delegations[account].delegate;
    }

    function delegate(address delegatee) external {
        _delegate({ delegator: msg.sender, delegatee: delegatee });
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        if (block.timestamp > expiry) revert IVeFxsVotingDelegation.SignatureExpired();
        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );
        if (nonce != $nonces[signer]++) revert IVeFxsVotingDelegation.InvalidSignatureNonce();
        _delegate(signer, delegatee);
    }

    /**
     * @param delegator Account whos votes will transferred from.
     * @param delegatee New account delegator will delegate to.
     * @dev An account can only delegate to one account at a time. The previous delegation will be overwritten.
     * @dev To undelegate, `delegatee` should be address(0)
     */
    function _delegate(address delegator, address delegatee) internal {
        if (delegator == delegatee) revert IVeFxsVotingDelegation.IncorrectSelfDelegation();

        IVeFxsVotingDelegation.Delegation memory previousDelegation = $delegations[delegator];
        if (previousDelegation.delegate == address(0) && delegatee == address(0)) {
            revert IVeFxsVotingDelegation.AlreadyDelegatedToSelf();
        }
        uint256 checkpointTimestamp = ((block.timestamp / 1 days) * 1 days) + 1 days;
        IVeFxsVotingDelegation.NormalizedVeFxsInfo memory _normalizedDelegatorVeFxsInfo = _getNormalizedVeFxsInfo(
            delegator,
            checkpointTimestamp
        );

        if (previousDelegation.timestamp == checkpointTimestamp) {
            revert IVeFxsVotingDelegation.AlreadyDelegatedThisEpoch();
        }

        _moveVotingPowerFromPreviousDelegate({
            previousDelegation: previousDelegation,
            checkpointTimestamp: checkpointTimestamp
        });

        _moveVotingPowerToNewDelegate({
            newDelegate: delegatee,
            delegatorVeFxsInfo: _normalizedDelegatorVeFxsInfo,
            checkpointTimestamp: checkpointTimestamp
        });

        $delegations[delegator] = IVeFxsVotingDelegation.Delegation({
            delegate: delegatee,
            previousDelegate: previousDelegation.delegate,
            timestamp: SafeCast.toUint48(checkpointTimestamp),
            bias: SafeCast.toUint128(_normalizedDelegatorVeFxsInfo.bias),
            slope: SafeCast.toUint96(_normalizedDelegatorVeFxsInfo.slope),
            expiry: SafeCast.toUint48(_normalizedDelegatorVeFxsInfo.expiry),
            fxs: SafeCast.toUint128(_normalizedDelegatorVeFxsInfo.fxs)
        });

        emit DelegateChanged({
            delegator: delegator,
            fromDelegate: previousDelegation.delegate,
            toDelegate: delegatee
        });
    }

    /**
     * @notice Get the most recently recorded rate of voting power decrease for `account`
     * @param account Address of the user wallet
     */
    function _getNormalizedVeFxsInfo(
        address account,
        uint256 checkpointTimestamp
    ) private view returns (IVeFxsVotingDelegation.NormalizedVeFxsInfo memory _return) {
        // most recent epoch
        uint256 epoch = VE_FXS.user_point_epoch(account);
        // values for account at the most recent epoch
        (int128 userBias, int128 userSlope, , , uint256 userFxs) = VE_FXS.user_point_history({
            _addr: account,
            _idx: epoch
        });
        _return.slope = SafeCast.toUint256(userSlope);
        _return.fxs = userFxs;
        _return.expiry = VE_FXS.locked(account).end;

        if (_return.expiry <= checkpointTimestamp) revert IVeFxsVotingDelegation.CantDelegateLockExpired();

        uint256 lastUpdate = VE_FXS.user_point_history__ts({ _addr: account, _idx: epoch });
        // normalize bias to unix epoch, so all biases can be added and subtracted directly
        _return.bias = SafeCast.toUint256(userBias) + _return.slope * lastUpdate;
    }

    function _checkpointLookup(
        IVeFxsVotingDelegation.DelegateCheckpoint[] storage _checkpoints,
        uint256 timestamp
    ) private view returns (IVeFxsVotingDelegation.DelegateCheckpoint memory) {
        uint256 _checkpointsLength = _checkpoints.length;

        // What the newest checkpoint could be for timestamp (rounded to whole days). It will be earlier when checkpoints are sparse.
        uint256 roundedDownTimestamp = (timestamp / 1 days) * 1 days;
        // Newest checkpoint's timestamp (already rounded to whole days)
        uint256 lastCheckpointTimestamp = _checkpointsLength > 0 ? _checkpoints[_checkpointsLength - 1].timestamp : 0;
        // The furthest back a checkpoint will ever be is the number of days delta between timestamp and the last
        // checkpoints timestamp. This happens when there was a checkpoint written every single day over that period.
        // If roundedDownTimestamp > lastCheckpointTimestamp that means that we can just use the last index as
        // the checkpoint.
        uint256 delta = lastCheckpointTimestamp > roundedDownTimestamp
            ? (lastCheckpointTimestamp - roundedDownTimestamp) / 1 days
            : 0;
        // low index is equal to the last checkpoints index minus the index delta
        uint256 low = (_checkpointsLength > 0 && _checkpointsLength - 1 > delta) ? _checkpointsLength - 1 - delta : 0;

        uint256 high = _checkpointsLength;
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_checkpoints[mid].timestamp > timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        IVeFxsVotingDelegation.DelegateCheckpoint memory empty;
        return high == 0 ? empty : _checkpoints[high - 1];
    }

    /**
     * @dev Used in _delegate() when an account changes delegation
     */
    function _moveVotingPowerFromPreviousDelegate(
        IVeFxsVotingDelegation.Delegation memory previousDelegation,
        uint256 checkpointTimestamp
    ) private {
        // Remove voting power from previous delegate, if they exist
        if (previousDelegation.delegate != address(0)) {
            // Get the last Checkpoint for previous delegate
            IVeFxsVotingDelegation.DelegateCheckpoint[] storage previousDelegationCheckpoints = $checkpoints[
                previousDelegation.delegate
            ];
            uint256 _accountCheckpointsLength = previousDelegationCheckpoints.length;
            // NOTE: we know that _accountsCheckpointLength > 0 because we have already checked that the previous delegation exists
            IVeFxsVotingDelegation.DelegateCheckpoint memory _lastCheckpoint = previousDelegationCheckpoints[
                _accountCheckpointsLength - 1
            ];
            uint256 oldWeightOldDelegate = _getVoteWeight(previousDelegation.delegate, checkpointTimestamp);

            // Handle Expirations

            // Only subtract when the delegator's expiration is in the future. This way, the former delegates voting power
            // will still properly expire for proposals that happen between previousDelegation.expiry and a new delegation.
            // See testExpiredLockRedelegateNoVotingWeight().
            if (previousDelegation.expiry > checkpointTimestamp) {
                // Calculations
                IVeFxsVotingDelegation.Expiration memory _expiration = $expirations[previousDelegation.delegate][
                    previousDelegation.expiry
                ];
                unchecked {
                    _expiration.bias -= SafeCast.toUint96(previousDelegation.bias);
                    _expiration.slope -= SafeCast.toUint64(previousDelegation.slope);
                    _expiration.fxs -= SafeCast.toUint96(previousDelegation.fxs);
                }

                // Effects
                $expirations[previousDelegation.delegate][previousDelegation.expiry] = _expiration;
            }

            {
                // Calculate new checkpoint
                IVeFxsVotingDelegation.DelegateCheckpoint memory _newCheckpoint = _calculateCheckpoint({
                    _previousCheckpoint: _lastCheckpoint,
                    account: previousDelegation.delegate,
                    _isDeltaPositive: false,
                    deltaBias: previousDelegation.bias,
                    deltaSlope: previousDelegation.slope,
                    deltaFxs: previousDelegation.fxs,
                    checkpointTimestamp: checkpointTimestamp,
                    previousDelegationExpiry: previousDelegation.expiry
                });

                // Write new checkpoint
                _writeCheckpoint({
                    userDelegationCheckpoints: previousDelegationCheckpoints,
                    _accountCheckpointsLength: _accountCheckpointsLength,
                    _newCheckpoint: _newCheckpoint,
                    _lastCheckpoint: _lastCheckpoint
                });
            }

            emit DelegateVotesChanged(
                previousDelegation.delegate,
                oldWeightOldDelegate,
                _getVoteWeight(previousDelegation.delegate, checkpointTimestamp)
            );
        }
    }

    function _moveVotingPowerToNewDelegate(
        address newDelegate,
        IVeFxsVotingDelegation.NormalizedVeFxsInfo memory delegatorVeFxsInfo,
        uint256 checkpointTimestamp
    ) private {
        // Add voting power to new delegate
        if (newDelegate != address(0)) {
            // Get the last checkpoint for the new delegate
            IVeFxsVotingDelegation.DelegateCheckpoint[] storage newDelegateCheckpoints = $checkpoints[newDelegate];
            uint256 _accountCheckpointsLength = newDelegateCheckpoints.length;
            IVeFxsVotingDelegation.DelegateCheckpoint memory _lastCheckpoint = _accountCheckpointsLength == 0
                ? IVeFxsVotingDelegation.DelegateCheckpoint(0, 0, 0, 0)
                : newDelegateCheckpoints[_accountCheckpointsLength - 1];
            uint256 oldWeightNewDelegate = _getVoteWeight(newDelegate, checkpointTimestamp);

            // Handle expiration
            // Calculations
            IVeFxsVotingDelegation.Expiration memory _expiration = $expirations[newDelegate][delegatorVeFxsInfo.expiry];
            unchecked {
                _expiration.bias += SafeCast.toUint96(delegatorVeFxsInfo.bias);
                _expiration.slope += SafeCast.toUint64(delegatorVeFxsInfo.slope);
                _expiration.fxs += SafeCast.toUint96(delegatorVeFxsInfo.fxs);
            }
            // Effects
            $expirations[newDelegate][delegatorVeFxsInfo.expiry] = _expiration;

            // Calculate new checkpoint
            IVeFxsVotingDelegation.DelegateCheckpoint memory _newCheckpoint = _calculateCheckpoint({
                _previousCheckpoint: _lastCheckpoint,
                _isDeltaPositive: true,
                account: newDelegate,
                deltaBias: delegatorVeFxsInfo.bias,
                deltaSlope: delegatorVeFxsInfo.slope,
                deltaFxs: delegatorVeFxsInfo.fxs,
                checkpointTimestamp: checkpointTimestamp,
                previousDelegationExpiry: 0 // not used
            });

            // Write new checkpoint
            _writeCheckpoint({
                userDelegationCheckpoints: newDelegateCheckpoints,
                _accountCheckpointsLength: _accountCheckpointsLength,
                _newCheckpoint: _newCheckpoint,
                _lastCheckpoint: _lastCheckpoint
            });

            emit DelegateVotesChanged(
                newDelegate,
                oldWeightNewDelegate,
                _getVoteWeight(newDelegate, checkpointTimestamp)
            );
        }
    }

    function _calculateCheckpoint(
        IVeFxsVotingDelegation.DelegateCheckpoint memory _previousCheckpoint,
        address account,
        bool _isDeltaPositive,
        uint256 deltaBias,
        uint256 deltaSlope,
        uint256 deltaFxs,
        uint256 checkpointTimestamp,
        uint256 previousDelegationExpiry
    ) private view returns (IVeFxsVotingDelegation.DelegateCheckpoint memory _newCheckpoint) {
        // If this is the first checkpoint, create a new one and early return
        if (_previousCheckpoint.timestamp == 0) {
            return
                IVeFxsVotingDelegation.DelegateCheckpoint({
                    timestamp: SafeCast.toUint128(checkpointTimestamp),
                    normalizedBias: SafeCast.toUint128(deltaBias),
                    normalizedSlope: SafeCast.toUint128(deltaSlope),
                    totalFxs: SafeCast.toUint128(deltaFxs)
                });
        }

        _newCheckpoint.timestamp = _previousCheckpoint.timestamp;
        _newCheckpoint.normalizedBias = _previousCheckpoint.normalizedBias;
        _newCheckpoint.normalizedSlope = _previousCheckpoint.normalizedSlope;
        _newCheckpoint.totalFxs = _previousCheckpoint.totalFxs;

        unchecked {
            // Add or subtract the delta to the previous checkpoint
            if (_isDeltaPositive) {
                _newCheckpoint.normalizedBias += SafeCast.toUint128(deltaBias);
                _newCheckpoint.normalizedSlope += SafeCast.toUint128(deltaSlope);
                _newCheckpoint.totalFxs += SafeCast.toUint128(deltaFxs);
            } else {
                // only subtract the weight from this account if it hasn't already expired in a previous checkpoint
                if (previousDelegationExpiry > _previousCheckpoint.timestamp) {
                    _newCheckpoint.normalizedBias -= SafeCast.toUint128(deltaBias);
                    _newCheckpoint.normalizedSlope -= SafeCast.toUint128(deltaSlope);
                    _newCheckpoint.totalFxs -= SafeCast.toUint128(deltaFxs);
                }
            }

            // If there have been expirations, add them to the adjustments by subtracting them from the checkpoint
            if (_newCheckpoint.timestamp != checkpointTimestamp) {
                (uint256 totalExpiredBias, uint256 totalExpiredSlope, uint256 totalExpiredFxs) = _calculateExpirations(
                    account,
                    _newCheckpoint.timestamp,
                    checkpointTimestamp
                );

                _newCheckpoint.timestamp = SafeCast.toUint128(checkpointTimestamp);
                _newCheckpoint.normalizedBias -= SafeCast.toUint128(totalExpiredBias);
                _newCheckpoint.normalizedSlope -= SafeCast.toUint128(totalExpiredSlope);
                _newCheckpoint.totalFxs -= SafeCast.toUint128(totalExpiredFxs);
            }
        }
    }

    function _writeCheckpoint(
        IVeFxsVotingDelegation.DelegateCheckpoint[] storage userDelegationCheckpoints,
        uint256 _accountCheckpointsLength,
        IVeFxsVotingDelegation.DelegateCheckpoint memory _newCheckpoint,
        IVeFxsVotingDelegation.DelegateCheckpoint memory _lastCheckpoint
    ) internal {
        if (_accountCheckpointsLength > 0 && _lastCheckpoint.timestamp == _newCheckpoint.timestamp) {
            userDelegationCheckpoints[_accountCheckpointsLength - 1] = _newCheckpoint;
        } else {
            userDelegationCheckpoints.push(_newCheckpoint);
        }
    }

    /**
     * @notice Generate a summation of bias, slopes, and fxs for all accounts whose decay expires
     * during a specified time window
     * @param account Delegate account to generate expiration bias and slopes for
     * @param start Timestamp to start the summations from. The start is not included.
     * @param end Timestamp to end to summations. The end is included.
     */
    function _calculateExpirations(
        address account,
        uint256 start,
        uint256 end
    ) private view returns (uint256 totalBias, uint256 totalSlope, uint256 expiredFxs) {
        // Total values will always be less than or equal to a checkpoint's values
        unchecked {
            uint256 currentWeek = WEEK + (start / WEEK) * WEEK;
            mapping(uint256 => IVeFxsVotingDelegation.Expiration) storage delegateExpirations = $expirations[account];
            while (currentWeek <= end) {
                IVeFxsVotingDelegation.Expiration memory expiration = delegateExpirations[currentWeek];
                totalBias += expiration.bias;
                totalSlope += expiration.slope;
                expiredFxs += expiration.fxs;
                currentWeek += WEEK;
            }
        }
    }
}
