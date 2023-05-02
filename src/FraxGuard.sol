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
// ========================= FraxGuard ================================
// ====================================================================
// A Gnosis Safe Guard that only allows calls to GnosisSafe.execTransaction()
// if the privileged signer has already called GnosisSafe.approveHash() and
// the caller is a Safe owner.

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch

import { IERC165 } from "@gnosis.pm/contracts/interfaces/IERC165.sol";
import { GuardManager, Guard } from "@gnosis.pm/contracts/base/GuardManager.sol";
import { ISafe, Enum } from "./interfaces/ISafe.sol";

contract FraxGuard is IERC165, Guard {
    address public immutable FRAX_GOVERNOR_OMEGA_ADDRESS;

    constructor(address _fraxGovernorOmega) {
        FRAX_GOVERNOR_OMEGA_ADDRESS = _fraxGovernorOmega;
    }

    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory, // signature
        address msgSender
    ) external {
        ISafe safe = ISafe(msg.sender);
        bytes32 txHash = safe.getTransactionHash({
            to: to,
            value: value,
            data: data,
            operation: operation,
            safeTxGas: safeTxGas,
            baseGas: baseGas,
            gasPrice: gasPrice,
            gasToken: gasToken,
            refundReceiver: refundReceiver,
            _nonce: safe.nonce() - 1 // nonce gets incremented before this function is called
        });
        if (
            !safe.isOwner(msgSender) ||
            safe.approvedHashes({ signer: FRAX_GOVERNOR_OMEGA_ADDRESS, txHash: txHash }) != 1
        ) {
            revert Unauthorized();
        }
    }

    function checkAfterExecution(bytes32 txHash, bool success) external {}

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return
            interfaceId == type(Guard).interfaceId || // 0xe6d7a83a
            interfaceId == type(IERC165).interfaceId; // 0x01ffc9a7
    }

    error Unauthorized();
}
