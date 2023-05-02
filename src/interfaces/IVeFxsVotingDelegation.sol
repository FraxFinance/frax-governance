// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IVeFxsVotingDelegation {
    /// A representation of a delegate and all its delegators at a particular timestamp
    struct DelegateCheckpoint {
        uint128 normalizedBias;
        uint128 totalFxs;
        // _________
        uint128 normalizedSlope;
        uint128 timestamp; // Rounded up to the nearest day
    }

    /// Represents the total bias, slope, and FXS amount of all accounts that expire for a specific delegate
    /// in a particular week
    struct Expiration {
        uint96 bias;
        uint96 fxs;
        uint64 slope;
    }

    /// Represents the values of a single delegation at the time `delegate()` is called,
    /// to be subtracted when removing delegation
    struct Delegation {
        uint128 bias;
        uint128 fxs;
        // _________
        address previousDelegate;
        uint96 slope;
        // __________
        address delegate;
        uint48 timestamp;
        uint48 expiry;
    }

    // Only used in memory
    struct NormalizedVeFxsInfo {
        uint256 bias;
        uint256 slope;
        uint256 fxs;
        uint256 expiry;
    }

    function $checkpoints(
        address,
        uint256
    ) external view returns (uint128 normalizedBias, uint128 totalFxs, uint128 normalizedSlope, uint128 timestamp);

    function $delegations(
        address
    )
        external
        view
        returns (
            uint128 bias,
            uint128 fxs,
            address previousDelegate,
            uint96 slope,
            address delegate,
            uint48 timestamp,
            uint48 expiry
        );

    function $expirations(address, uint256) external view returns (uint256 bias, uint128 fxs, uint128 slope);

    function $nonces(address) external view returns (uint256);

    function CLOCK_MODE() external pure returns (string memory);

    function DELEGATION_TYPEHASH() external view returns (bytes32);

    function VE_FXS() external view returns (address);

    function VOTE_WEIGHT_MULTIPLIER() external view returns (uint256);

    function WEEK() external view returns (uint256);

    function calculateExpirations(address account) external view returns (DelegateCheckpoint memory);

    function clock() external view returns (uint48);

    function delegate(address delegatee) external;

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;

    function delegates(address account) external view returns (address);

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    function getCheckpoint(address account, uint32 pos) external view returns (DelegateCheckpoint memory);

    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);

    function getVotes(address account) external view returns (uint256);

    function getVotes(address account, uint256 timepoint) external view returns (uint256);

    function writeNewCheckpointForExpirations(address account) external;

    error InvalidSignatureNonce();
    error SignatureExpired();
    error IncorrectSelfDelegation();
    error AlreadyDelegatedToSelf();
    error AlreadyDelegatedThisEpoch();
    error CantDelegateLockExpired();
    error BlockNumberInFuture();
    error TimestampInFuture();
    error NoExpirations();
}
