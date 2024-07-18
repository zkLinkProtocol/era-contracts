// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IMailbox} from "../../chain-interfaces/IMailbox.sol";
import {IZkLink} from "../../chain-interfaces/IZkLink.sol";
import {ITransactionFilterer} from "../../chain-interfaces/ITransactionFilterer.sol";
import {Merkle} from "../../libraries/Merkle.sol";
import {PriorityQueue, PriorityOperation} from "../../libraries/PriorityQueue.sol";
import {TransactionValidator} from "../../libraries/TransactionValidator.sol";
import {WritePriorityOpParams, L2CanonicalTransaction, L2Message, L2Log, TxStatus, BridgehubL2TransactionRequest, ForwardL2Request} from "../../../common/Messaging.sol";
import {FeeParams, PubdataPricingMode, SecondaryChain, SecondaryChainSyncStatus, SecondaryChainOp} from "../ZkSyncHyperchainStorage.sol";
import {UncheckedMath} from "../../../common/libraries/UncheckedMath.sol";
import {L2ContractHelper} from "../../../common/libraries/L2ContractHelper.sol";
import {AddressAliasHelper} from "../../../vendor/AddressAliasHelper.sol";
import {ZkSyncHyperchainBase} from "./ZkSyncHyperchainBase.sol";
import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA, ETH_TOKEN_ADDRESS, L1_GAS_PER_PUBDATA_BYTE, L2_L1_LOGS_TREE_DEFAULT_LEAF_HASH, PRIORITY_OPERATION_L2_TX_TYPE, PRIORITY_EXPIRATION, MAX_NEW_FACTORY_DEPS} from "../../../common/Config.sol";
import {L2_BOOTLOADER_ADDRESS, L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR} from "../../../common/L2ContractAddresses.sol";

import {IL1SharedBridge} from "../../../bridge/interfaces/IL1SharedBridge.sol";

// While formally the following import is not used, it is needed to inherit documentation from it
import {IZkSyncHyperchainBase} from "../../chain-interfaces/IZkSyncHyperchainBase.sol";

/// @title zkSync Mailbox contract providing interfaces for L1 <-> L2 interaction.
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
contract MailboxFacet is ZkSyncHyperchainBase, IMailbox {
    using UncheckedMath for uint256;
    using PriorityQueue for PriorityQueue.Queue;

    /// @inheritdoc IZkSyncHyperchainBase
    string public constant override getName = "MailboxFacet";

    /// @dev The forward request type hash
    bytes32 public constant FORWARD_REQUEST_TYPE_HASH =
        keccak256(
            "ForwardL2Request(address gateway,bool isContractCall,address sender,uint256 txId,address contractAddressL2,uint256 l2Value,bytes32 l2CallDataHash,uint256 l2GasLimit,uint256 l2GasPricePerPubdata,bytes32 factoryDepsHash,address refundRecipient)"
        );

    /// @dev Era's chainID
    uint256 immutable ERA_CHAIN_ID;

    constructor(uint256 _eraChainId) {
        ERA_CHAIN_ID = _eraChainId;
    }

    /// @inheritdoc IMailbox
    function transferEthToSharedBridge() external onlyBaseTokenBridge {
        require(s.chainId == ERA_CHAIN_ID, "Mailbox: transferEthToSharedBridge only available for Era on mailbox");

        uint256 amount = address(this).balance;
        address baseTokenBridgeAddress = s.baseTokenBridge;
        IL1SharedBridge(baseTokenBridgeAddress).receiveEth{value: amount}(ERA_CHAIN_ID);
    }

    function receiveEth() external payable {
        require(s.baseTokenBridge == msg.sender, "Mailbox: receiveEth not shared bridge");
    }

    /// @notice when requesting transactions through the bridgehub
    function bridgehubRequestL2Transaction(
        BridgehubL2TransactionRequest calldata _request
    ) external onlyBridgehub returns (bytes32 canonicalTxHash) {
        canonicalTxHash = _requestL2TransactionSender(_request);
    }

    /// @inheritdoc IMailbox
    function proveL2MessageInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Message memory _message,
        bytes32[] calldata _proof
    ) public view returns (bool) {
        return _proveL2LogInclusion(_batchNumber, _index, _L2MessageToLog(_message), _proof);
    }

    /// @inheritdoc IMailbox
    function proveL2LogInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Log memory _log,
        bytes32[] calldata _proof
    ) external view returns (bool) {
        return _proveL2LogInclusion(_batchNumber, _index, _log, _proof);
    }

    /// @inheritdoc IMailbox
    function proveL1ToL2TransactionStatus(
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof,
        TxStatus _status
    ) public view returns (bool) {
        // Bootloader sends an L2 -> L1 log only after processing the L1 -> L2 transaction.
        // Thus, we can verify that the L1 -> L2 transaction was included in the L2 batch with specified status.
        //
        // The semantics of such L2 -> L1 log is always:
        // - sender = L2_BOOTLOADER_ADDRESS
        // - key = hash(L1ToL2Transaction)
        // - value = status of the processing transaction (1 - success & 0 - fail)
        // - isService = true (just a conventional value)
        // - l2ShardId = 0 (means that L1 -> L2 transaction was processed in a rollup shard, other shards are not available yet anyway)
        // - txNumberInBatch = number of transaction in the batch
        L2Log memory l2Log = L2Log({
            l2ShardId: 0,
            isService: true,
            txNumberInBatch: _l2TxNumberInBatch,
            sender: L2_BOOTLOADER_ADDRESS,
            key: _l2TxHash,
            value: bytes32(uint256(_status))
        });
        return _proveL2LogInclusion(_l2BatchNumber, _l2MessageIndex, l2Log, _merkleProof);
    }

    /// @dev Prove that a specific L2 log was sent in a specific L2 batch number
    function _proveL2LogInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Log memory _log,
        bytes32[] calldata _proof
    ) internal view returns (bool) {
        require(_batchNumber <= s.totalBatchesExecuted, "xx");

        bytes32 hashedLog = keccak256(
            // solhint-disable-next-line func-named-parameters
            abi.encodePacked(_log.l2ShardId, _log.isService, _log.txNumberInBatch, _log.sender, _log.key, _log.value)
        );
        // Check that hashed log is not the default one,
        // otherwise it means that the value is out of range of sent L2 -> L1 logs
        require(hashedLog != L2_L1_LOGS_TREE_DEFAULT_LEAF_HASH, "tw");

        // It is ok to not check length of `_proof` array, as length
        // of leaf preimage (which is `L2_TO_L1_LOG_SERIALIZE_SIZE`) is not
        // equal to the length of other nodes preimages (which are `2 * 32`)

        bytes32 calculatedRootHash = Merkle.calculateRoot(_proof, _index, hashedLog);
        bytes32 actualRootHash = s.l2LogsRootHashes[_batchNumber];

        return actualRootHash == calculatedRootHash;
    }

    /// @dev Convert arbitrary-length message to the raw l2 log
    function _L2MessageToLog(L2Message memory _message) internal pure returns (L2Log memory) {
        return
            L2Log({
                l2ShardId: 0,
                isService: true,
                txNumberInBatch: _message.txNumberInBatch,
                sender: L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR,
                key: bytes32(uint256(uint160(_message.sender))),
                value: keccak256(_message.data)
            });
    }

    /// @inheritdoc IMailbox
    function l2TransactionBaseCost(
        uint256 _gasPrice,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit
    ) public view returns (uint256) {
        uint256 l2GasPrice = _deriveL2GasPrice(_gasPrice, _l2GasPerPubdataByteLimit);
        return l2GasPrice * _l2GasLimit;
    }

    /// @inheritdoc IMailbox
    function syncL2Requests(
        address _secondaryChainGateway,
        uint256 _newTotalSyncedPriorityTxs,
        bytes32 _syncHash,
        uint256 _forwardEthAmount
    ) external payable onlyGateway {
        // Secondary chain should be registered
        SecondaryChain memory secondaryChain = s.secondaryChains[_secondaryChainGateway];
        require(secondaryChain.valid, "ssc");

        // Check newTotalSyncedPriorityTxs
        require(
            _newTotalSyncedPriorityTxs <= secondaryChain.totalPriorityTxs &&
                _newTotalSyncedPriorityTxs > secondaryChain.totalSyncedPriorityTxs,
            "spt"
        );

        // Check sync hash at new point
        SecondaryChainSyncStatus memory syncStatus = s.secondaryChainSyncStatus[_secondaryChainGateway][
            _newTotalSyncedPriorityTxs - 1
        ];
        require(syncStatus.hash == _syncHash, "ssh");

        // Check forward eth amount
        SecondaryChainSyncStatus memory lastSyncStatus;
        if (secondaryChain.totalSyncedPriorityTxs > 0) {
            lastSyncStatus = s.secondaryChainSyncStatus[_secondaryChainGateway][
                secondaryChain.totalSyncedPriorityTxs - 1
            ];
        }
        require(syncStatus.amount - lastSyncStatus.amount == _forwardEthAmount, "sfm");
        require(msg.value == _forwardEthAmount, "smv");
        // Transfer eth to L1SharedBridge
        IL1SharedBridge(s.baseTokenBridge).bridgehubDepositBaseToken{value: msg.value}(
            s.chainId,
            msg.sender,
            ETH_TOKEN_ADDRESS,
            msg.value
        );

        // Update totalSyncedPriorityTxs
        s.secondaryChains[_secondaryChainGateway].totalSyncedPriorityTxs = _newTotalSyncedPriorityTxs;
        emit SyncL2Requests(_secondaryChainGateway, _newTotalSyncedPriorityTxs, _syncHash, _forwardEthAmount);
    }

    /// @inheritdoc IMailbox
    function syncRangeBatchRoot(
        address[] calldata _secondaryChainGateways,
        uint256 _fromBatchNumber,
        uint256 _toBatchNumber
    ) external payable nonReentrant onlyValidator {
        // The batch should be executed
        require(_fromBatchNumber <= _toBatchNumber, "brf");
        require(_toBatchNumber <= s.totalBatchesExecuted, "brt");

        bytes32 rangeBatchRootHash = s.l2LogsRootHashes[_fromBatchNumber];
        unchecked {
            for (uint256 i = _fromBatchNumber + 1; i <= _toBatchNumber; ++i) {
                bytes32 l2LogsRootHash = s.l2LogsRootHashes[i];
                rangeBatchRootHash = Merkle._efficientHash(rangeBatchRootHash, l2LogsRootHash);
            }
        }

        uint256 gatewayLength = _secondaryChainGateways.length;
        bytes[] memory gatewayDataList = new bytes[](gatewayLength);
        uint256 totalForwardEthAmount = 0;
        for (uint256 i = 0; i < gatewayLength; i = i.uncheckedInc()) {
            // Secondary chain should be registered
            address _secondaryChainGateway = _secondaryChainGateways[i];
            SecondaryChain memory secondaryChain = s.secondaryChains[_secondaryChainGateway];
            require(secondaryChain.valid, "bsc");
            uint256 _forwardEthAmount = secondaryChain.totalPendingWithdraw;
            // Withdraw eth amount impossible overflow
            totalForwardEthAmount += _forwardEthAmount;
            s.secondaryChains[_secondaryChainGateway].totalPendingWithdraw = 0;
            // Send range batch root to secondary chain
            bytes memory gatewayCallData = abi.encodeCall(
                IZkLink.syncRangeBatchRoot,
                (_fromBatchNumber, _toBatchNumber, rangeBatchRootHash, _forwardEthAmount)
            );
            gatewayDataList[i] = abi.encode(_secondaryChainGateway, _forwardEthAmount, gatewayCallData);
            emit SyncRangeBatchRoot({
                secondaryChainGateway: _secondaryChainGateway,
                fromBatchNumber: _fromBatchNumber,
                toBatchNumber: _toBatchNumber,
                rangeBatchRootHash: rangeBatchRootHash,
                forwardEthAmount: _forwardEthAmount
            });
        }

        // Withdraw eth from L1SharedBridge
        IL1SharedBridge(s.baseTokenBridge).eraWithdrawETH(s.chainId, totalForwardEthAmount);
        // Forward fee to gateway
        s.gateway.sendMessage{value: msg.value + totalForwardEthAmount}(
            totalForwardEthAmount,
            abi.encode(gatewayDataList)
        );
    }

    /// @inheritdoc IMailbox
    function syncL2TxHash(bytes32 _l2TxHash) external payable nonReentrant {
        SecondaryChainOp memory op = s.canonicalTxToSecondaryChainOp[_l2TxHash];
        require(op.gateway != address(0), "tsc");

        // Send l2 tx hash to secondary chain by gateway
        bytes[] memory gatewayDataList = new bytes[](1);
        bytes memory callData = abi.encodeCall(IZkLink.syncL2TxHash, (op.canonicalTxHash, _l2TxHash));
        gatewayDataList[0] = abi.encode(op.gateway, 0, callData);
        // Forward fee to gateway
        s.gateway.sendMessage{value: msg.value}(0, abi.encode(gatewayDataList));
        emit SyncL2TxHash(_l2TxHash);
    }

    /// @notice Derives the price for L2 gas in base token to be paid.
    /// @param _l1GasPrice The gas price on L1
    /// @param _gasPerPubdata The price for each pubdata byte in L2 gas
    /// @return The price of L2 gas in the base token
    function _deriveL2GasPrice(uint256 _l1GasPrice, uint256 _gasPerPubdata) internal view returns (uint256) {
        FeeParams memory feeParams = s.feeParams;
        require(s.baseTokenGasPriceMultiplierDenominator > 0, "Mailbox: baseTokenGasPriceDenominator not set");
        uint256 l1GasPriceConverted = (_l1GasPrice * s.baseTokenGasPriceMultiplierNominator) /
            s.baseTokenGasPriceMultiplierDenominator;
        uint256 pubdataPriceBaseToken;
        if (feeParams.pubdataPricingMode == PubdataPricingMode.Rollup) {
            // slither-disable-next-line divide-before-multiply
            pubdataPriceBaseToken = L1_GAS_PER_PUBDATA_BYTE * l1GasPriceConverted;
        }

        // slither-disable-next-line divide-before-multiply
        uint256 batchOverheadBaseToken = uint256(feeParams.batchOverheadL1Gas) * l1GasPriceConverted;
        uint256 fullPubdataPriceBaseToken = pubdataPriceBaseToken +
            batchOverheadBaseToken /
            uint256(feeParams.maxPubdataPerBatch);

        uint256 l2GasPrice = feeParams.minimalL2GasPrice + batchOverheadBaseToken / uint256(feeParams.maxL2GasPerBatch);
        uint256 minL2GasPriceBaseToken = (fullPubdataPriceBaseToken + _gasPerPubdata - 1) / _gasPerPubdata;

        return Math.max(l2GasPrice, minL2GasPriceBaseToken);
    }

    /// @inheritdoc IMailbox
    function finalizeEthWithdrawal(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) external nonReentrant {
        require(s.chainId == ERA_CHAIN_ID, "Mailbox: finalizeEthWithdrawal only available for Era on mailbox");
        IL1SharedBridge(s.baseTokenBridge).finalizeWithdrawal({
            _chainId: ERA_CHAIN_ID,
            _l2BatchNumber: _l2BatchNumber,
            _l2MessageIndex: _l2MessageIndex,
            _l2TxNumberInBatch: _l2TxNumberInBatch,
            _message: _message,
            _merkleProof: _merkleProof
        });
    }

    /// @inheritdoc IMailbox
    function increaseSecondaryChainTotalPendingWithdraw(
        address _secondaryChainGateway,
        uint256 _amount
    ) external onlyBaseTokenBridge {
        s.secondaryChains[_secondaryChainGateway].totalPendingWithdraw += _amount;
    }

    ///  @inheritdoc IMailbox
    function requestL2Transaction(
        address _contractL2,
        uint256 _l2Value,
        bytes calldata _calldata,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit,
        bytes[] calldata _factoryDeps,
        address _refundRecipient
    ) external payable returns (bytes32 canonicalTxHash) {
        require(s.chainId == ERA_CHAIN_ID, "Mailbox: legacy interface only available for Era");
        canonicalTxHash = _requestL2TransactionSender(
            BridgehubL2TransactionRequest({
                sender: msg.sender,
                contractL2: _contractL2,
                mintValue: msg.value,
                l2Value: _l2Value,
                l2GasLimit: _l2GasLimit,
                l2Calldata: _calldata,
                l2GasPerPubdataByteLimit: _l2GasPerPubdataByteLimit,
                factoryDeps: _factoryDeps,
                refundRecipient: _refundRecipient
            })
        );
        IL1SharedBridge(s.baseTokenBridge).bridgehubDepositBaseToken{value: msg.value}(
            s.chainId,
            msg.sender,
            ETH_TOKEN_ADDRESS,
            msg.value
        );
    }

    /// @inheritdoc IMailbox
    function forwardRequestL2Transaction(
        ForwardL2Request calldata _request
    ) external payable nonReentrant onlyValidator returns (bytes32 canonicalTxHash) {
        require(s.chainId == ERA_CHAIN_ID, "Mailbox: legacy interface only available for Era");
        bytes32 secondaryChainCanonicalTxHash = hashForwardL2Request(_request);
        {
            SecondaryChain memory secondaryChain = s.secondaryChains[_request.gateway];
            require(secondaryChain.valid, "fsc");
            require(secondaryChain.totalPriorityTxs == _request.txId, "fst");

            SecondaryChainSyncStatus memory syncStatus;
            if (secondaryChain.totalPriorityTxs == 0) {
                syncStatus.hash = secondaryChainCanonicalTxHash;
                syncStatus.amount = _request.l2Value;
            } else {
                syncStatus = s.secondaryChainSyncStatus[_request.gateway][secondaryChain.totalPriorityTxs - 1];
                syncStatus.hash = keccak256(abi.encodePacked(syncStatus.hash, secondaryChainCanonicalTxHash));
                syncStatus.amount = syncStatus.amount + _request.l2Value;
            }
            s.secondaryChainSyncStatus[_request.gateway][secondaryChain.totalPriorityTxs] = syncStatus;
            s.secondaryChains[_request.gateway].totalPriorityTxs = secondaryChain.totalPriorityTxs + 1;
        }

        // Here we manually assign fields for the struct to prevent "stack too deep" error
        WritePriorityOpParams memory params;
        params.txId = s.priorityQueue.getTotalPriorityTxs();
        params.l2GasPrice = _deriveL2GasPrice(tx.gasprice, _request.l2GasPricePerPubdata);
        params.expirationTimestamp = uint64(block.timestamp + PRIORITY_EXPIRATION); // Safe to cast

        uint256 baseCost = params.l2GasPrice * _request.l2GasLimit;
        // Checking that the user provided enough ether to pay for the transaction.
        // Using a new scope to prevent "stack too deep" error
        {
            require(msg.value >= baseCost, "fmv"); // The `msg.value` doesn't cover the transaction cost
            uint256 leftMsgValue = msg.value - baseCost;
            if (leftMsgValue > 0) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, ) = msg.sender.call{value: leftMsgValue}("");
                require(success, "fse");
            }
        }
        // If the `_refundRecipient` is a smart contract, we apply the L1 to L2 alias to prevent foot guns.
        address refundRecipient = _request.refundRecipient;
        if (refundRecipient.code.length > 0) {
            refundRecipient = AddressAliasHelper.applyL1ToL2Alias(refundRecipient);
        }
        params.request = BridgehubL2TransactionRequest({
            sender: _request.sender,
            contractL2: _request.contractAddressL2,
            mintValue: baseCost + _request.l2Value,
            l2Value: _request.l2Value,
            l2GasLimit: _request.l2GasLimit,
            l2Calldata: _request.l2CallData,
            l2GasPerPubdataByteLimit: _request.l2GasPricePerPubdata,
            factoryDeps: _request.factoryDeps,
            refundRecipient: refundRecipient
        });

        canonicalTxHash = _writePriorityOp(params);
        s.canonicalTxToSecondaryChainOp[canonicalTxHash] = SecondaryChainOp(
            _request.gateway,
            _request.txId,
            secondaryChainCanonicalTxHash
        );
        s.secondaryToCanonicalTxHash[secondaryChainCanonicalTxHash] = canonicalTxHash;

        // Transfer eth to L1SharedBridge
        IL1SharedBridge(s.baseTokenBridge).bridgehubDepositBaseToken{value: baseCost}(
            s.chainId,
            msg.sender,
            ETH_TOKEN_ADDRESS,
            baseCost
        );
    }

    function _requestL2TransactionSender(
        BridgehubL2TransactionRequest memory _request
    ) internal nonReentrant returns (bytes32 canonicalTxHash) {
        // Check that the transaction is allowed by the filterer (if the filterer is set).
        if (s.transactionFilterer != address(0)) {
            require(
                ITransactionFilterer(s.transactionFilterer).isTransactionAllowed({
                    sender: _request.sender,
                    contractL2: _request.contractL2,
                    mintValue: _request.mintValue,
                    l2Value: _request.l2Value,
                    l2Calldata: _request.l2Calldata,
                    refundRecipient: _request.refundRecipient
                }),
                "tf"
            );
        }

        // Enforcing that `_request.l2GasPerPubdataByteLimit` equals to a certain constant number. This is needed
        // to ensure that users do not get used to using "exotic" numbers for _request.l2GasPerPubdataByteLimit, e.g. 1-2, etc.
        // VERY IMPORTANT: nobody should rely on this constant to be fixed and every contract should give their users the ability to provide the
        // ability to provide `_request.l2GasPerPubdataByteLimit` for each independent transaction.
        // CHANGING THIS CONSTANT SHOULD BE A CLIENT-SIDE CHANGE.
        require(_request.l2GasPerPubdataByteLimit == REQUIRED_L2_GAS_PRICE_PER_PUBDATA, "qp");

        WritePriorityOpParams memory params;
        params.request = _request;

        canonicalTxHash = _requestL2Transaction(params);
    }

    function _requestL2Transaction(WritePriorityOpParams memory _params) internal returns (bytes32 canonicalTxHash) {
        BridgehubL2TransactionRequest memory request = _params.request;

        require(request.factoryDeps.length <= MAX_NEW_FACTORY_DEPS, "uj");
        _params.txId = s.priorityQueue.getTotalPriorityTxs();

        // Checking that the user provided enough ether to pay for the transaction.
        _params.l2GasPrice = _deriveL2GasPrice(tx.gasprice, request.l2GasPerPubdataByteLimit);
        uint256 baseCost = _params.l2GasPrice * request.l2GasLimit;
        require(request.mintValue >= baseCost + request.l2Value, "mv"); // The `msg.value` doesn't cover the transaction cost

        request.refundRecipient = AddressAliasHelper.actualRefundRecipient(request.refundRecipient, request.sender);
        // Change the sender address if it is a smart contract to prevent address collision between L1 and L2.
        // Please note, currently zkSync address derivation is different from Ethereum one, but it may be changed in the future.
        // slither-disable-next-line tx-origin
        if (request.sender != tx.origin) {
            request.sender = AddressAliasHelper.applyL1ToL2Alias(request.sender);
        }

        // populate missing fields
        _params.expirationTimestamp = uint64(block.timestamp + PRIORITY_EXPIRATION); // Safe to cast

        canonicalTxHash = _writePriorityOp(_params);
    }

    function _serializeL2Transaction(
        WritePriorityOpParams memory _priorityOpParams
    ) internal pure returns (L2CanonicalTransaction memory transaction) {
        BridgehubL2TransactionRequest memory request = _priorityOpParams.request;
        transaction = L2CanonicalTransaction({
            txType: PRIORITY_OPERATION_L2_TX_TYPE,
            from: uint256(uint160(request.sender)),
            to: uint256(uint160(request.contractL2)),
            gasLimit: request.l2GasLimit,
            gasPerPubdataByteLimit: request.l2GasPerPubdataByteLimit,
            maxFeePerGas: uint256(_priorityOpParams.l2GasPrice),
            maxPriorityFeePerGas: uint256(0),
            paymaster: uint256(0),
            // Note, that the priority operation id is used as "nonce" for L1->L2 transactions
            nonce: uint256(_priorityOpParams.txId),
            value: request.l2Value,
            reserved: [request.mintValue, uint256(uint160(request.refundRecipient)), 0, 0],
            data: request.l2Calldata,
            signature: new bytes(0),
            factoryDeps: _hashFactoryDeps(request.factoryDeps),
            paymasterInput: new bytes(0),
            reservedDynamic: new bytes(0)
        });
    }

    /// @notice Stores a transaction record in storage & send event about that
    function _writePriorityOp(
        WritePriorityOpParams memory _priorityOpParams
    ) internal returns (bytes32 canonicalTxHash) {
        L2CanonicalTransaction memory transaction = _serializeL2Transaction(_priorityOpParams);

        bytes memory transactionEncoding = abi.encode(transaction);

        TransactionValidator.validateL1ToL2Transaction(
            transaction,
            transactionEncoding,
            s.priorityTxMaxGasLimit,
            s.feeParams.priorityTxMaxPubdata
        );

        canonicalTxHash = keccak256(transactionEncoding);

        s.priorityQueue.pushBack(
            PriorityOperation({
                canonicalTxHash: canonicalTxHash,
                expirationTimestamp: _priorityOpParams.expirationTimestamp,
                layer2Tip: uint192(0) // TODO: Restore after fee modeling will be stable. (SMA-1230)
            })
        );

        // Data that is needed for the operator to simulate priority queue offchain
        // solhint-disable-next-line func-named-parameters
        emit NewPriorityRequest(
            _priorityOpParams.txId,
            canonicalTxHash,
            _priorityOpParams.expirationTimestamp,
            transaction,
            _priorityOpParams.request.factoryDeps
        );
    }

    /// @notice Hashes the L2 bytecodes and returns them in the format in which they are processed by the bootloader
    function _hashFactoryDeps(bytes[] memory _factoryDeps) internal pure returns (uint256[] memory hashedFactoryDeps) {
        uint256 factoryDepsLen = _factoryDeps.length;
        hashedFactoryDeps = new uint256[](factoryDepsLen);
        for (uint256 i = 0; i < factoryDepsLen; i = i.uncheckedInc()) {
            bytes32 hashedBytecode = L2ContractHelper.hashL2Bytecode(_factoryDeps[i]);

            // Store the resulting hash sequentially in bytes.
            assembly {
                mstore(add(hashedFactoryDeps, mul(add(i, 1), 32)), hashedBytecode)
            }
        }
    }

    function hashForwardL2Request(ForwardL2Request memory _request) internal pure returns (bytes32) {
        return
            keccak256(
                // solhint-disable-next-line func-named-parameters
                abi.encode(
                    FORWARD_REQUEST_TYPE_HASH,
                    _request.gateway,
                    _request.isContractCall,
                    _request.sender,
                    _request.txId,
                    _request.contractAddressL2,
                    _request.l2Value,
                    keccak256(_request.l2CallData),
                    _request.l2GasLimit,
                    _request.l2GasPricePerPubdata,
                    keccak256(abi.encode(_request.factoryDeps)),
                    _request.refundRecipient
                )
            );
    }
}
