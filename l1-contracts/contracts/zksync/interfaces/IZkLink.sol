// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity 0.8.20;

/// @title ZkLink interface contract
/// @author zk.link
interface IZkLink {
    /// @notice Receive batch root from primary chain
    /// @param _batchNumber The batch number
    /// @param _l2LogsRootHash The L2 to L1 log root hash
    function syncBatchRoot(uint256 _batchNumber, bytes32 _l2LogsRootHash) external payable;
}
