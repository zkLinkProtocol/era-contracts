// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

interface IL2Gateway {
    /// @notice Send message to remote gateway
    /// @param value The msg value
    /// @param callData The call data
    function sendMessage(uint256 value, bytes memory callData) external payable;
}
