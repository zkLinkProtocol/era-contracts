// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity 0.8.19;

/// @title ZkLink interface contract
/// @author zk.link
interface IZkLink {
    /// @notice Receive batch root from primary chain
    /// @param _batchNumber The batch number
    /// @param _l2LogsRootHash The L2 to L1 log root hash
    function syncBatchRoot(uint256 _batchNumber, bytes32 _l2LogsRootHash) external;

    /// @notice Receive l2 tx hash from primary chain
    /// @param _l2TxHash The l2 tx hash on local chain
    /// @param _primaryChainL2TxHash The l2 tx hash on primary chain
    function syncL2TxHash(bytes32 _l2TxHash, bytes32 _primaryChainL2TxHash) external;
}
