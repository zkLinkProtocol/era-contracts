// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {PriorityOperation} from "../libraries/PriorityQueue.sol";
import {VerifierParams, UpgradeState, SecondaryChain, SecondaryChainSyncStatus, SecondaryChainOp} from "../Storage.sol";
import "./IBase.sol";
import {IL2Gateway} from "./IL2Gateway.sol";

/// @title The interface of the Getters Contract that implements functions for getting contract state from outside the blockchain.
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IGetters is IBase {
    /*//////////////////////////////////////////////////////////////
                            CUSTOM GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @return The gateway on local chain
    function getGateway() external view returns (IL2Gateway);

    /// @return The secondary chain status
    function getSecondaryChain(address gateway) external view returns (SecondaryChain memory);

    /// @return The secondary chain op sync status
    function getSecondaryChainSyncStatus(
        address gateway,
        uint256 priorityOpId
    ) external view returns (SecondaryChainSyncStatus memory);

    /// @return The secondary chain op info bind with tx
    function getSecondaryChainOp(bytes32 canonicalTxHash) external view returns (SecondaryChainOp memory);

    /// @return Return the canonical tx hash bind with secondary chain tx
    function getCanonicalTxHash(bytes32 secondaryChainCanonicalTxHash) external view returns (bytes32);

    /// @return The address of the verifier smart contract
    function getVerifier() external view returns (address);

    /// @return The address of the current governor
    function getGovernor() external view returns (address);

    /// @return The address of the pending governor
    function getPendingGovernor() external view returns (address);

    /// @return The total number of batches that were committed
    function getTotalBatchesCommitted() external view returns (uint256);

    /// @return The total number of batches that were committed & verified
    function getTotalBatchesVerified() external view returns (uint256);

    /// @return The total number of batches that were committed & verified & executed
    function getTotalBatchesExecuted() external view returns (uint256);

    /// @return The total number of priority operations that were added to the priority queue, including all processed ones
    function getTotalPriorityTxs() external view returns (uint256);

    /// @notice The function that returns the first unprocessed priority transaction.
    /// @dev Returns zero if and only if no operations were processed from the queue.
    /// @dev If all the transactions were processed, it will return the last processed index, so
    /// in case exactly *unprocessed* transactions are needed, one should check that getPriorityQueueSize() is greater than 0.
    /// @return Index of the oldest priority operation that wasn't processed yet
    function getFirstUnprocessedPriorityTx() external view returns (uint256);

    /// @return The number of priority operations currently in the queue
    function getPriorityQueueSize() external view returns (uint256);

    /// @return The first unprocessed priority operation from the queue
    function priorityQueueFrontOperation() external view returns (PriorityOperation memory);

    /// @return Whether the address has a validator access
    function isValidator(address _address) external view returns (bool);

    /// @return merkleRoot Merkle root of the tree with L2 logs for the selected batch
    function l2LogsRootHash(uint256 _batchNumber) external view returns (bytes32 merkleRoot);

    /// @notice For unfinalized (non executed) batches may change
    /// @dev returns zero for non-committed batches
    /// @return The hash of committed L2 batch.
    function storedBatchHash(uint256 _batchNumber) external view returns (bytes32);

    /// @return Bytecode hash of bootloader program.
    function getL2BootloaderBytecodeHash() external view returns (bytes32);

    /// @return Bytecode hash of default account (bytecode for EOA).
    function getL2DefaultAccountBytecodeHash() external view returns (bytes32);

    /// @return Verifier parameters.
    function getVerifierParams() external view returns (VerifierParams memory);

    /// @return Whether the diamond is frozen or not
    function isDiamondStorageFrozen() external view returns (bool);

    /// @return The current protocol version
    function getProtocolVersion() external view returns (uint256);

    /// @return The upgrade system contract transaction hash, 0 if the upgrade is not initialized
    function getL2SystemContractsUpgradeTxHash() external view returns (bytes32);

    /// @return The L2 batch number in which the upgrade transaction was processed.
    /// @dev It is equal to 0 in the following two cases:
    /// - No upgrade transaction has ever been processed.
    /// - The upgrade transaction has been processed and the batch with such transaction has been
    /// executed (i.e. finalized).
    function getL2SystemContractsUpgradeBatchNumber() external view returns (uint256);

    /// @return The maximum number of L2 gas that a user can request for L1 -> L2 transactions
    function getPriorityTxMaxGasLimit() external view returns (uint256);

    /// @return Whether a withdrawal has been finalized.
    /// @param _l2BatchNumber The L2 batch number within which the withdrawal happened.
    /// @param _l2MessageIndex The index of the L2->L1 message denoting the withdrawal.
    function isEthWithdrawalFinalized(uint256 _l2BatchNumber, uint256 _l2MessageIndex) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            DIAMOND LOUPE
    //////////////////////////////////////////////////////////////*/

    /// @notice Faсet structure compatible with the EIP-2535 diamond loupe
    /// @param addr The address of the facet contract
    /// @param selectors The NON-sorted array with selectors associated with facet
    struct Facet {
        address addr;
        bytes4[] selectors;
    }

    /// @return result All facet addresses and their function selectors
    function facets() external view returns (Facet[] memory);

    /// @return NON-sorted array with function selectors supported by a specific facet
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory);

    /// @return facets NON-sorted array of facet addresses supported on diamond
    function facetAddresses() external view returns (address[] memory facets);

    /// @return facet The facet address associated with a selector. Zero if the selector is not added to the diamond
    function facetAddress(bytes4 _selector) external view returns (address facet);

    /// @return Whether the selector can be frozen by the governor or always accessible
    function isFunctionFreezable(bytes4 _selector) external view returns (bool);

    /// @return isFreezable Whether the facet can be frozen by the governor or always accessible
    function isFacetFreezable(address _facet) external view returns (bool isFreezable);
}
