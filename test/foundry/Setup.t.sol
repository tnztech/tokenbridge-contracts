// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/interfaces/IERC20.sol";
import "./interfaces/ISavingsDai.sol";
import "./interfaces/IEternalStorageProxy.sol";
import "./interfaces/IXDaiForeignBridge.sol";



contract SetupTest is Test {

    address public initializer = address(11);
    address public alice = address(12);
    address public bob = address(13);
    address public proxyOwner = 0x57B11cC8F93f2cfeC4c1C5B95213f17cAD81332B;
    address public bridgeOwner = 0xf02796C7B84F10Fa866DAa7d5701A95f3131A727;
    address public gnosisInterestReceiver = 0xABCDEF00aBC0352436A70adDbF1bE34f3ea11016;
    
    ISavingsDai public sDAI;
    IERC20 public dai;
    address public bridgeAddress = 0x8659Cf2273438f9b5C1Eb367Def45007a7A16a24;
    IEternalStorageProxy public bridgeProxy;
    IXDaiForeignBridge public bridge;
    IXDaiForeignBridge public newImpl;
    IXDaiForeignBridge public initialImpl;
    uint256 public globalTime;

    function setUp() public payable {

        console.log("chainId %s",block.chainid);
        console.log("block %s",block.number);

        sDAI = ISavingsDai(0xD8134205b0328F5676aaeFb3B2a0DC15f4029d8C);
        dai = IERC20(0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844);
        IERC20 oldDAI = IERC20(0xdc31Ee1784292379Fbb2964b3B9C4124D8F89C60);
        bridgeProxy = IEternalStorageProxy(bridgeAddress);
        bridge = IXDaiForeignBridge(bridgeAddress);
        initialImpl = IXDaiForeignBridge(bridgeProxy.implementation());
        newImpl = IXDaiForeignBridge(vm.envAddress("NEW_IMPLEMENTATION"));

        uint size;
        address _a = address(newImpl);
        assembly {
            size := extcodesize(_a)
        }
        assertGt(size, 0);
        globalTime = block.timestamp;

        vm.deal(initializer, 100 ether);
        vm.deal(bridgeOwner, 100 ether);
        vm.deal(proxyOwner, 100 ether);
        vm.deal(alice, 10000 ether);
        vm.deal(bob, 100000 ether);

        deal(address(dai), alice, 100e18);
        deal(address(dai), address(bridgeProxy), oldDAI.balanceOf(address(bridgeProxy)));
        assertEq(dai.balanceOf(alice), 100e18);

        deal(address(dai), bob, 10000e18);
        assertEq(dai.balanceOf(bob), 10000e18);

        /*//////////////////////////////////////////////////////////////
                                DEPLOYMENTS
        //////////////////////////////////////////////////////////////*/
        uint256 initialInvested = bridge.investedAmount(address(dai));
        console.log("initially invested amount: %e, %s",initialInvested, block.timestamp);
        upgrade();
        uint256 afterInvested = bridge.investedAmount(address(dai));
        console.log("after invested amount: %e, %s",afterInvested, block.timestamp);

    }


    /*//////////////////////////////////////////////////////////////
                        INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function testInitialize() public{
        bool implInitialized = initialImpl.isInitialized();
        assertFalse(implInitialized);
        implInitialized = newImpl.isInitialized();
        assertFalse(implInitialized);
        implInitialized = bridge.isInitialized();
        assertTrue(implInitialized);
    }


    /*//////////////////////////////////////////////////////////////
                        UPGRADING PROXIES
    //////////////////////////////////////////////////////////////*/

    function upgrade() public {
        if (address(newImpl) != bridgeProxy.implementation()){
        vm.startPrank(proxyOwner);
        
        uint256 initialVersion = bridgeProxy.version();

        bridgeProxy.upgradeTo(initialVersion + 1, address(newImpl));

        assertEq(initialVersion + 1, bridgeProxy.version());
        assertEq(address(newImpl), bridgeProxy.implementation());
        console.log("upgraded bridge to version %s", initialVersion + 1);
        vm.stopPrank();
        testSetNewErc20Token();
        vm.startPrank(bridgeOwner);
        bridge.initializeInterest(address(dai), 100 ether, 1000000, gnosisInterestReceiver);
        bridge.investDai();
        skipTime(1 days);
        vm.stopPrank();
        }
    }

    function testSetNewErc20Token() public{

        vm.startPrank(bridgeOwner);
        bridge.setNewErc20Token(address(dai));
        assertEq(bridge.erc20token(), address(dai));
        assertEq(bridge.daiToken(), address(dai));
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