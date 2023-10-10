// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "../chain-interfaces/IVerifier.sol";
import "../Verifier.sol";
import "../../common/interfaces/IAllowList.sol";
import "../../bridgehead/bridgehead-interfaces/IBridgeheadForProof.sol";
import "../../bridgehead/chain-interfaces/IBridgeheadChain.sol";
import "../../common/Messaging.sol";

// import "./libraries/PriorityQueue.sol";

// /// @notice Indicates whether an upgrade is initiated and if yes what type
// /// @param None Upgrade is NOT initiated
// /// @param Transparent Fully transparent upgrade is initiated, upgrade data is publicly known
// /// @param Shadow Shadow upgrade is initiated, upgrade data is hidden
// enum ProofUpgradeState {
//     None,
//     Transparent,
//     Shadow
// }

// /// @dev Logically separated part of the storage structure, which is responsible for everything related to proxy upgrades and diamond cuts
// /// @param proposedUpgradeHash The hash of the current upgrade proposal, zero if there is no active proposal
// /// @param state Indicates whether an upgrade is initiated and if yes what type
// /// @param securityCouncil Address which has the permission to approve instant upgrades (expected to be a Gnosis multisig)
// /// @param approvedBySecurityCouncil Indicates whether the security council has approved the upgrade
// /// @param proposedUpgradeTimestamp The timestamp when the upgrade was proposed, zero if there are no active proposals
// /// @param currentProposalId The serial number of proposed upgrades, increments when proposing a new one
// struct ProofUpgradeStorage {
//     bytes32 proposedUpgradeHash;
//     ProofUpgradeState state;
//     address securityCouncil;
//     bool approvedBySecurityCouncil;
//     uint40 proposedUpgradeTimestamp;
//     uint40 currentProposalId;
// }

/// @dev storing all storage variables for zkSync facets
/// NOTE: It is used in a proxy, so it is possible to add new variables to the end
/// but NOT to modify already existing variables or change their order.
/// NOTE: variables prefixed with '__DEPRECATED_' are deprecated and shouldn't be used.
/// Their presence is maintained for compatibility and to prevent storage collision.
struct ProofStorage {
    /// @dev Storage of variables needed for deprecated diamond cut facet
    uint256[7] __DEPRECATED_diamondCutStorage;
    /// @notice Address which will exercise governance over the network i.e. change validator set, conduct upgrades
    address governor;
    /// @notice Address
    address admin;
    /// @notice Address that the governor proposed as one that will replace it
    address pendingGovernor;
    /// @notice Address of the factory
    address bridgehead;
    /// @notice chainContract
    mapping(uint256 => address) proofChainContract;
    /// @dev Verifier contract. Used to verify aggregated proof for Batchs
    address verifier;
    /// @notice Total number of executed Batchs i.e. Batchs[totalBatchsExecuted] points at the latest executed Batch (Batch 0 is genesis)
    mapping(uint256 => uint256) totalBatchsExecuted;
    /// @notice Total number of proved Batchs i.e. Batchs[totalBatchsProved] points at the latest proved Batch
    mapping(uint256 => uint256) totalBatchsVerified;
    /// @notice Total number of committed Batchs i.e. Batchs[totalBatchsCommitted] points at the latest committed Batch
    mapping(uint256 => uint256) totalBatchsCommitted;
    /// @dev Stored hashed StoredBatch for Batch number
    mapping(uint256 => mapping(uint256 => bytes32)) storedBatchHashes;
    // /// @dev Stored root hashes of L2 -> L1 logs
    // mapping(uint256 => bytes32) l2LogsRootHashes;
    // /// @dev Container that stores transactions requested from L1
    // PriorityQueue.Queue priorityQueue;
    /// @dev The smart contract that manages the list with permission to call contract functions
    address allowList;
    /// @dev Batch hash zero, calculated at initialization
    bytes32 storedBatchZero;
    /// @dev Stored cutData for diamond cut
    bytes32 cutHash;
    /// @notice Part of the configuration parameters of ZKP circuits. Used as an input for the verifier smart contract
    VerifierParams verifierParams;
    /// @notice Bytecode hash of bootloader program.
    /// @dev Used as an input to zkp-circuit.
    bytes32 l2BootloaderBytecodeHash;
    /// @notice Bytecode hash of default account (bytecode for EOA).
    /// @dev Used as an input to zkp-circuit.
    bytes32 l2DefaultAccountBytecodeHash;
    /// @dev The maximum number of the L2 gas that a user can request for L1 -> L2 transactions
    /// @dev This is the maximum number of L2 gas that is available for the "body" of the transaction, i.e.
    /// without overhead for proving the Batch.
    uint256 priorityTxMaxGasLimit;
    /// @dev Storage of variables needed for upgrade facet
    // ProofUpgradeStorage upgrades;
    // /// @dev A mapping L2 Batch number => message number => flag.
    // /// @dev The L2 -> L1 log is sent for every withdrawal, so this mapping is serving as
    // /// a flag to indicate that the message was already processed.
    // /// @dev Used to indicate that eth withdrawal was already processed
    // mapping(uint256 => mapping(uint256 => bool)) isEthWithdrawalFinalized;
    // /// @dev The most recent withdrawal time and amount reset
    // uint256 __DEPRECATED_lastWithdrawalLimitReset;
    // /// @dev The accumulated withdrawn amount during the withdrawal limit window
    // uint256 __DEPRECATED_withdrawnAmountInWindow;
    // /// @dev A mapping user address => the total deposited amount by the user
    // mapping(address => uint256) totalDepositedAmountPerUser;
    /// @dev Stores the protocol version. Note, that the protocol version may not only encompass changes to the
    /// smart contracts, but also to the node behavior.
    uint256 protocolVersion;
    /// @dev Hash of the system contract upgrade transaction. If 0, then no upgrade transaction needs to be done.
    mapping(uint256 => bytes32) l2SystemContractsUpgradeTxHash;
    /// @dev Batch number where the upgrade transaction has happened. If 0, then no upgrade transaction has happened yet.
    mapping(uint256 => uint256) l2SystemContractsUpgradeBatchNumber;
}
