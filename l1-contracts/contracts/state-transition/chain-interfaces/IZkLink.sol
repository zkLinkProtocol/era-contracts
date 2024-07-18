// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity 0.8.19;

/// @title ZkLink interface contract
/// @author zk.link
interface IZkLink {
    /// @notice Receive range batch root from primary chain
    /// @param _fromBatchNumber The batch number from
    /// @param _toBatchNumber The batch number to
    /// @param _rangeRootHash The range root hash
    /// @param _forwardEthAmount The forward eth amount
    function syncRangeBatchRoot(
        uint256 _fromBatchNumber,
        uint256 _toBatchNumber,
        bytes32 _rangeRootHash,
        uint256 _forwardEthAmount
    ) external payable;

    /// @notice Receive l2 tx hash from primary chain
    /// @param _l2TxHash The l2 tx hash on local chain
    /// @param _primaryChainL2TxHash The l2 tx hash on primary chain
    function syncL2TxHash(bytes32 _l2TxHash, bytes32 _primaryChainL2TxHash) external;
}
