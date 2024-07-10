// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/// @title L1 Bridge contract interface
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IL1Bridge {
    error FunctionNotSupported();

    event DepositInitiated(
        bytes32 indexed l2DepositTxHash,
        address indexed from,
        address indexed to,
        address l1Token,
        uint256 amount
    );

    event DepositToMergeInitiated(
        bytes32 indexed l2DepositTxHash,
        address indexed from,
        address indexed to,
        address l1Token,
        uint256 amount,
        bool toMerge
    );

    event WithdrawalFinalized(address indexed to, address indexed l1Token, uint256 amount);

    event ClaimedFailedDeposit(address indexed to, address indexed l1Token, uint256 amount);

    event CCTPBurn(
        uint64 indexed _nonce,
        address indexed _mintRecipient,
        address indexed _burnToken,
        uint256 _amount,
        uint32 _destinationDomain
    );

    event CCTPReceive(bytes message, bytes attestation);

    event RebalanceL2(
        bytes32 indexed l2RebalanceTxHash,
        address indexed _l2Token,
        address indexed _destL2Erc20Bridge,
        uint256 _amount
    );

    function isWithdrawalFinalized(uint256 _l2BatchNumber, uint256 _l2MessageIndex) external view returns (bool);

    function deposit(
        address _l2Receiver,
        address _l1Token,
        uint256 _amount,
        uint256 _l2TxGasLimit,
        uint256 _l2TxGasPerPubdataByte,
        address _refundRecipient
    ) external payable returns (bytes32 txHash);

    function depositToMerge(
        address _l2Receiver,
        address _l1Token,
        uint256 _amount,
        uint256 _l2TxGasLimit,
        uint256 _l2TxGasPerPubdataByte,
        address _refundRecipient
    ) external payable returns (bytes32 txHash);

    function claimFailedDeposit(
        address _depositSender,
        address _l1Token,
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof
    ) external;

    function finalizeWithdrawal(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) external;

    function l2TokenAddress(address _l1Token) external view returns (address);

    function l2Bridge() external view returns (address);
}
