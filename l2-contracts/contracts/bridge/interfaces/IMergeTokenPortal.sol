// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IMergeTokenPortal {
    /// @notice Source token info
    /// @param isSupported Is the source token supported
    /// @param isLocked Is the source token locked
    /// @param balance Source token balance
    /// @param depositLimit Source token deposit limit
    struct SourceTokenInfo {
        bool isSupported;
        bool isLocked;
        address mergeToken;
        uint256 balance;
        uint256 depositLimit;
    }

    /**
     * @notice Get source token info
     * @param _sourceToken Source token address
     * @return Source token info
     */
    function getSourceTokenInfos(address _sourceToken) external view returns (SourceTokenInfo memory);

    /**
     * @notice Deposit source token to mint merge token
     * @param _sourceToken Source token address
     * @param _amount Deposit amount
     * @param _receiver Receiver address
     */
    function deposit(address _sourceToken, uint256 _amount, address _receiver) external;

    /**
     * @notice Burn merge token and get source token back
     * @param _sourceToken Source token address
     * @param _amount Withdraw amount
     * @param _receiver Recceiver address
     */
    function withdraw(address _sourceToken, uint256 _amount, address _receiver) external;
}
