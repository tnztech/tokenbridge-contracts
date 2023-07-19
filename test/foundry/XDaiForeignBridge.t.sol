// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import 'forge-std/console.sol';
import 'forge-std/interfaces/IERC20.sol';
import "contracts/interfaces/ISavingsDai.sol";
import "contracts/upgradeability/EternalStorageProxy.sol";
import "contracts/upgradeable_contracts/erc20_to_native/XDaiForeignBridge.sol";

