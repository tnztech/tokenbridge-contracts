// SPDX-License-Identifier: gpl-2.0
pragma solidity 0.4.24;

//import 'forge-std/Script.sol';
//import 'forge-std/console.sol';
import "contracts/upgradeable_contracts/erc20_to_native/XDaiForeignBridge.sol";

contract XDaiForeignBridgeDeployer /*is Script */{

    event NewDeployment(address);

    function run() external {

        /*//////////////////////////////////////////////////////////////
                                KEY MANAGEMENT
        //////////////////////////////////////////////////////////////*/
/*
        uint256 deployerPrivateKey = 0;
        string memory mnemonic = vm.envString('MNEMONIC');

        if (bytes(mnemonic).length > 30) {
            deployerPrivateKey = vm.deriveKey(mnemonic, 0);
        } else {
            deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        }

        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.rememberKey(deployerPrivateKey);
        console.log('Deployer: %s', deployer);
   */

        /*//////////////////////////////////////////////////////////////
                                DEPLOYMENTS
        //////////////////////////////////////////////////////////////*/

        XDaiForeignBridge xdaiBridge = new XDaiForeignBridge();
   //     console.log('Deployed XDaiForeignBridge: %s', address(xdaiBridge));
        emit NewDeployment(xdaiBridge);
    //    vm.stopBroadcast();
    }
}
