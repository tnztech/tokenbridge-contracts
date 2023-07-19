// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import 'forge-std/console.sol';
import 'forge-std/interfaces/IERC20.sol';
import "contracts/interfaces/ISavingsDai.sol";
import "contracts/upgradeability/EternalStorageProxy.sol";
import "contracts/upgradeable_contracts/erc20_to_native/XDaiForeignBridge.sol";



contract SetupTest is Test {

    address public initializer = address(9);
    address public alice = address(10);
    address public bob = address(11);
    address public bridgeOwner = 0x42F38ec5A75acCEc50054671233dfAC9C0E7A3F6;
    
    GnosisSavingsDAI public sDAI = ISavingsDai(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    IERC20 public dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    EternalStorageProxy public bridgeProxy = EternalStorageProxy(0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016);
    XDaiForeignBridge public bridgeImpl;
    uint256 public globalTime;

    function setUp() public payable {

        vm.createSelectFork("gnosis",28920197);

        globalTime = block.timestamp;

        vm.deal(initializer, 100 ether);
        vm.deal(alice, 10000 ether);
        vm.deal(bob, 100000 ether);

        deal(address(dai), alice, 100e18);
        assertEq(dai.balanceOf(alice), 100e18);

        deal(address(dai), bob, 10000e18);
        assertEq(dai.balanceOf(bob), 10000e18);

        /*//////////////////////////////////////////////////////////////
                                DEPLOYMENTS
        //////////////////////////////////////////////////////////////*/
        vm.startPrank(initializer);

        bridgeImpl = new XDaiForeignBridge();
        console.log('Deployed XDaiForeignBridge: %s', address(bridgeImpl));

        vm.stopPrank();

        testUpgrade();

    }


    /*//////////////////////////////////////////////////////////////
                        INITIALIZER
    //////////////////////////////////////////////////////////////*/


    /*//////////////////////////////////////////////////////////////
                        UPGRADING PROXIES
    //////////////////////////////////////////////////////////////*/

    function testUpgrade() public {

        vm.startPrank(owner);
        
        initialVersion = bridgeProxy.version();
        initialImpl = bridgeProxy.implementation();
        bridgeProxy.upgradeTo(initialVersion + 1, address(bridgeImpl));

        assertEq(initialVersion + 1, bridgeProxy.version());
        assertNotEq(initialImpl, bridgeProxy.implementation());
        console.log("upgraded bridge to version %s", initialVersion + 1);

        vm.stopPrank();

    }


    /*//////////////////////////////////////////////////////////////
                        UTILS
    //////////////////////////////////////////////////////////////*/

    function teleport(uint256 _timestamp) public{
        globalTime = _timestamp;
        vm.warp(globalTime);
    }

    function skipTime(uint256 secs) public{
        globalTime += secs;
        vm.warp(globalTime);
    }
}