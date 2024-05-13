// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IAdmin} from "../interfaces/IAdmin.sol";
import {Diamond} from "../libraries/Diamond.sol";
import {MAX_GAS_PER_TRANSACTION} from "../Config.sol";
import {FeeParams} from "../Storage.sol";
import {Base} from "./Base.sol";
import {IL2Gateway} from "../interfaces/IL2Gateway.sol";

// While formally the following import is not used, it is needed to inherit documentation from it
import {IBase} from "../interfaces/IBase.sol";
import {IDAVerifier} from "../interfaces/IDAVerifier.sol";

/// @title Admin Contract controls access rights for contract management.
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
contract AdminFacet is Base, IAdmin {
    /// @inheritdoc IBase
    string public constant override getName = "AdminFacet";

    /// @inheritdoc IAdmin
    function setGateway(IL2Gateway _gateway) external onlyGovernor {
        require(address(s.gateway) == address(0), "g9");
        require(address(_gateway) != address(0), "ga");
        s.gateway = _gateway;
        emit InitGateway(_gateway);
    }

    /// @inheritdoc IAdmin
    function setSecondaryChainGateway(address _gateway, bool _active) external onlyGateway {
        if (s.secondaryChains[_gateway].valid != _active) {
            s.secondaryChains[_gateway].valid = _active;
            emit SecondaryChainStatusUpdate(_gateway, _active);
        }
    }

    /// @inheritdoc IAdmin
    function setDAVerifier(IDAVerifier _daVerifier) external onlyGovernor {
        require(address(_daVerifier) != address(0), "gb");
        if (s.daVerifier != _daVerifier) {
            s.daVerifier = _daVerifier;
            emit DAVerifierUpdate(_daVerifier);
        }
    }

    /// @inheritdoc IAdmin
    function setPendingGovernor(address _newPendingGovernor) external onlyGovernor {
        // Save previous value into the stack to put it into the event later
        address oldPendingGovernor = s.pendingGovernor;
        // Change pending governor
        s.pendingGovernor = _newPendingGovernor;
        emit NewPendingGovernor(oldPendingGovernor, _newPendingGovernor);
    }

    /// @inheritdoc IAdmin
    function acceptGovernor() external {
        address pendingGovernor = s.pendingGovernor;
        require(msg.sender == pendingGovernor, "n4"); // Only proposed by current governor address can claim the governor rights

        address previousGovernor = s.governor;
        s.governor = pendingGovernor;
        delete s.pendingGovernor;

        emit NewPendingGovernor(pendingGovernor, address(0));
        emit NewGovernor(previousGovernor, pendingGovernor);
    }

    /// @inheritdoc IAdmin
    function setPendingAdmin(address _newPendingAdmin) external onlyGovernor {
        // Save previous value into the stack to put it into the event later
        address oldPendingAdmin = s.pendingAdmin;
        // Change pending admin
        s.pendingAdmin = _newPendingAdmin;
        emit NewPendingAdmin(oldPendingAdmin, _newPendingAdmin);
    }

    /// @inheritdoc IAdmin
    function acceptAdmin() external {
        address pendingAdmin = s.pendingAdmin;
        require(msg.sender == pendingAdmin, "n4"); // Only proposed by current admin address can claim the admin rights

        address previousAdmin = s.admin;
        s.admin = pendingAdmin;
        delete s.pendingAdmin;

        emit NewPendingAdmin(pendingAdmin, address(0));
        emit NewAdmin(previousAdmin, pendingAdmin);
    }

    /// @inheritdoc IAdmin
    function setValidator(address _validator, bool _active) external onlyGovernorOrAdmin {
        s.validators[_validator] = _active;
        emit ValidatorStatusUpdate(_validator, _active);
    }

    /// @inheritdoc IAdmin
    function setPorterAvailability(bool _zkPorterIsAvailable) external onlyGovernor {
        // Change the porter availability
        s.zkPorterIsAvailable = _zkPorterIsAvailable;
        emit IsPorterAvailableStatusUpdate(_zkPorterIsAvailable);
    }

    /// @inheritdoc IAdmin
    function setPriorityTxMaxGasLimit(uint256 _newPriorityTxMaxGasLimit) external onlyGovernor {
        require(_newPriorityTxMaxGasLimit <= MAX_GAS_PER_TRANSACTION, "n5");

        uint256 oldPriorityTxMaxGasLimit = s.priorityTxMaxGasLimit;
        s.priorityTxMaxGasLimit = _newPriorityTxMaxGasLimit;
        emit NewPriorityTxMaxGasLimit(oldPriorityTxMaxGasLimit, _newPriorityTxMaxGasLimit);
    }

    /// @inheritdoc IAdmin
    function changeFeeParams(FeeParams calldata _newFeeParams) external onlyGovernor {
        // Double checking that the new fee params are valid, i.e.
        // the maximal pubdata per batch is not less than the maximal pubdata per priority transaction.
        require(_newFeeParams.maxPubdataPerBatch >= _newFeeParams.priorityTxMaxPubdata, "n6");

        FeeParams memory oldFeeParams = s.feeParams;
        s.feeParams = _newFeeParams;

        emit NewFeeParams(oldFeeParams, _newFeeParams);
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAdmin
    function executeUpgrade(Diamond.DiamondCutData calldata _diamondCut) external onlyGovernor {
        Diamond.diamondCut(_diamondCut);
        emit ExecuteUpgrade(_diamondCut);
    }

    /*//////////////////////////////////////////////////////////////
                            CONTRACT FREEZING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAdmin
    function freezeDiamond() external onlyGovernor {
        Diamond.DiamondStorage storage diamondStorage = Diamond.getDiamondStorage();

        require(!diamondStorage.isFrozen, "a9"); // diamond proxy is frozen already
        diamondStorage.isFrozen = true;

        emit Freeze();
    }

    /// @inheritdoc IAdmin
    function unfreezeDiamond() external onlyGovernorOrAdmin {
        Diamond.DiamondStorage storage diamondStorage = Diamond.getDiamondStorage();

        require(diamondStorage.isFrozen, "a7"); // diamond proxy is not frozen
        diamondStorage.isFrozen = false;

        emit Unfreeze();
    }
}
