// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/// @title The interface of the DAVerifier contract, responsible for the commitment verification of batch.
/// @author zk.link
/// @custom:security-contact security@matterlabs.dev
interface IDAVerifier {
    /// @notice Is a valid commitment.
    function isValidCommitment(bytes32 commitment) external view returns (bool);
}
