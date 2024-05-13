// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IDAVerifier.sol";

/// @notice A tuple of data root with metadata. Each data root is associated
///  with a Celestia block height.
/// @dev `availableDataRoot` in
///  https://github.com/celestiaorg/celestia-specs/blob/master/src/specs/data_structures.md#header
struct DataRootTuple {
    // Celestia block height the data root was included in.
    // Genesis block is height = 0.
    // First queryable block is height = 1.
    uint256 height;
    // Data root.
    bytes32 dataRoot;
}

/// @notice Merkle Tree Proof structure.
struct BinaryMerkleProof {
    // List of side nodes to verify and calculate tree.
    bytes32[] sideNodes;
    // The key of the leaf to verify.
    uint256 key;
    // The number of leaves in the tree
    uint256 numLeaves;
}

/// @notice Data Availability Oracle interface.
interface IDAOracle {
    /// @notice Verify a Data Availability attestation.
    /// @param _tupleRootNonce Nonce of the tuple root to prove against.
    /// @param _tuple Data root tuple to prove inclusion of.
    /// @param _proof Binary Merkle tree proof that `tuple` is in the root at `_tupleRootNonce`.
    /// @return `true` is proof is valid, `false` otherwise.
    function verifyAttestation(
        uint256 _tupleRootNonce,
        DataRootTuple memory _tuple,
        BinaryMerkleProof memory _proof
    ) external view returns (bool);
}

/// @author zk.link
/// @notice The celestia verifier that integrate with BlockStream.
/// @dev https://docs.celestia.org/developers/blobstream-contracts
contract CelestiaDAVerifier is IDAVerifier {
    IDAOracle public immutable DA_ORACLE;

    mapping(bytes32 commitment => bool) public validCommitment;

    constructor(IDAOracle _daOracle) {
        DA_ORACLE = _daOracle;
    }

    function isValidCommitment(bytes32 _commitment) external view returns (bool) {
        return validCommitment[_commitment];
    }

    function verifyCommitment(
        uint256 _tupleRootNonce,
        DataRootTuple calldata _tuple,
        BinaryMerkleProof calldata _proof
    ) external {
        require(DA_ORACLE.verifyAttestation(_tupleRootNonce, _tuple, _proof), "Invalid attestation");
        // The `dataRoot` of tuple is `commitment` of batch
        validCommitment[_tuple.dataRoot] = true;
    }
}
