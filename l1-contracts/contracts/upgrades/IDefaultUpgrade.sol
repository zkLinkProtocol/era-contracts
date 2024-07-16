// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ProposedUpgrade} from "./BaseZkSyncUpgrade.sol";

interface IDefaultUpgrade {
    function upgrade(ProposedUpgrade calldata _upgrade) external returns (bytes32);
}
