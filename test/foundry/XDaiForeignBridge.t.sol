// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/interfaces/IERC20.sol";
import "./interfaces/ISavingsDai.sol";
import "./interfaces/IEternalStorageProxy.sol";
import "./interfaces/IXDaiForeignBridge.sol";
import "./Setup.t.sol";

contract XDaiForeignBridgeTest is SetupTest {

    event DailyLimitChanged(uint256 newLimit);
    event ExecutionDailyLimitChanged(uint256 newLimit);
    event GasPriceChanged(uint256 gasPrice);
    event OwnershipTransferred(address previousOwner, address newOwner);
    event PaidInterest(address indexed token, address to, uint256 value);
    event RelayedMessage(address recipient, uint256 value, bytes32 transactionHash);
    event RequiredBlockConfirmationChanged(uint256 requiredBlockConfirmations);
    event UserRequestForAffirmation(address recipient, uint256 value);

    function invariantMetadata() public {
        assertEq(address(sDAI.dai()), address(dai));
        assertEq(address(bridge.erc20token()), address(dai));
        assertEq(alice, address(10));
        assertEq(bob, address(11));
    }

    /*//////////////////////////////////////////////////////////////
                        CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function testFuzzRefillBridge(uint256 minCashThreshold) public {
        vm.assume(minCashThreshold > 0);
        setMinCashThreshold(address(dai), minCashThreshold);
        uint256 initialBalance = dai.balanceOf(bridgeAddress);
        if (initialBalance < minCashThreshold) {
            bridge.refillBridge();
        } else {
            vm.expectRevert(bytes("Bridge is Filled"));
            bridge.refillBridge();
        }
        if (minCashThreshold > (dai.balanceOf(bridgeAddress) + bridge.investedAmount(address(dai)))) {
            assertLt(dai.balanceOf(bridgeAddress), bridge.minCashThreshold(address(dai)));
        } else {
            assertGe(dai.balanceOf(bridgeAddress), bridge.minCashThreshold(address(dai)));
        }
        assertGe(dai.balanceOf(bridgeAddress), initialBalance);
    }

    function testFuzzInvestDai(uint256 minCashThreshold, uint256 minInterestPaid) public {
        vm.assume(minCashThreshold > 1 ether);
        vm.assume(minInterestPaid > 1 ether);
        initializeInterest(minCashThreshold, minInterestPaid);
        setMinCashThreshold(address(dai), minCashThreshold);
        setMinInterestPaid(address(dai), minInterestPaid);
        uint256 initialBalance = dai.balanceOf(bridgeAddress);
        uint256 initialInvested = bridge.investedAmount(address(dai));

        if (initialBalance > minCashThreshold) {
            bridge.investDai();
            assertLt(dai.balanceOf(bridgeAddress), initialBalance);
            assertGt(bridge.investedAmount(address(dai)), initialInvested);
        } else {
            vm.expectRevert(bytes("Balance too Low"));
            bridge.investDai();
        }
        
    }

    function testFuzzPayInterest(uint256 minCashThreshold, uint256 minInterestPaid) public {
        address token = address(dai);
        vm.assume(minCashThreshold > 0);
        vm.assume(minInterestPaid > 0);

        testFuzzInvestDai(minCashThreshold, minInterestPaid);
        uint256 initialBalance = dai.balanceOf(bridgeAddress);
        uint256 initialInvested = bridge.investedAmount(token);
        skip(1000);
        uint256 collectable = bridge.interestAmount(token);

        if (collectable >= bridge.minInterestPaid(token)) {
            vm.expectEmit(); 
            emit UserRequestForAffirmation(gnosisInterestReceiver, collectable); 
            bridge.payInterest(token);
            assertGt(dai.balanceOf(bridgeAddress), initialBalance);
            assertLt(bridge.interestAmount(token), collectable);
        } else {
            vm.expectRevert(bytes("Collectable interest too low"));
            bridge.payInterest(token);
        }     
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIG PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetDailyLimit(uint256 _dailyLimit) public {
        vm.assume(_dailyLimit > bridge.maxPerTx());
        vm.startPrank(bridgeOwner);
        bridge.setDailyLimit(_dailyLimit);
        vm.stopPrank();
    }

    function testFuzzSetExecutionDailyLimit(uint256 _dailyLimit) public {
        vm.startPrank(bridgeOwner);
        vm.assume(_dailyLimit > bridge.executionMaxPerTx());
        bridge.setExecutionDailyLimit(_dailyLimit);
        vm.stopPrank();
    }

    function testFuzzSetExecutionMaxPerTx() public {
        uint256 _maxPerTx;
        vm.startPrank(bridgeOwner);
        vm.assume(_maxPerTx < bridge.executionDailyLimit());
        bridge.setExecutionMaxPerTx(_maxPerTx);
        vm.stopPrank();
    }

    function testSetGasPrice(uint256 _gasPrice) public {
        vm.assume(_gasPrice > 0);
        vm.startPrank(bridgeOwner);
        bridge.setGasPrice(_gasPrice);
        vm.stopPrank();
    }

    function initializeInterest(
        uint256 _minCashThreshold,
        uint256 _minInterestPaid
    ) public {
        vm.startPrank(bridgeOwner);

        vm.expectRevert(bytes("Token not supported"));
        bridge.initializeInterest(address(sDAI), _minCashThreshold, _minInterestPaid, gnosisInterestReceiver);

        if (bridge.isInterestEnabled(address(dai)) == false){
            bridge.initializeInterest(address(dai), _minCashThreshold, _minInterestPaid, gnosisInterestReceiver);
        }
        else {
            vm.expectRevert(bytes("Interest already enabled"));
            bridge.initializeInterest(address(dai), _minCashThreshold, _minInterestPaid, gnosisInterestReceiver);
        }

        vm.stopPrank();
    }

    function testDisableInterest() public {
        vm.startPrank(bridgeOwner);
        bridge.disableInterest(address(dai));
        vm.stopPrank();
    }

    function setInterestReceiver(address _token, address _receiver) public {
        vm.startPrank(bridgeOwner);
        bridge.setInterestReceiver(_token, _receiver);
        vm.stopPrank();
    }

    function testSetMaxPerTx(uint256 _maxPerTx) public {
        vm.startPrank(bridgeOwner);
        vm.assume(_maxPerTx > bridge.minPerTx() && _maxPerTx < bridge.dailyLimit());
        bridge.setMaxPerTx(_maxPerTx);
        vm.stopPrank();
    }

    function setMinCashThreshold(address _token, uint256 _minCashThreshold) public {
        vm.startPrank(bridgeOwner);
        bridge.setMinCashThreshold(_token, _minCashThreshold);
        vm.stopPrank();
    }

    function setMinInterestPaid(address _token, uint256 _minInterestPaid) public {
        vm.startPrank(bridgeOwner);
        bridge.setMinInterestPaid(_token, _minInterestPaid);
        vm.stopPrank();
    }

    function testSetMinPerTx(uint256 _minPerTx) public {
        vm.startPrank(bridgeOwner);
        vm.assume(_minPerTx > 0 && _minPerTx < bridge.dailyLimit() && _minPerTx < bridge.maxPerTx());
        bridge.setMinPerTx(_minPerTx);
        vm.stopPrank();
    }

    function setPayMaster(address _paymaster) public {
        vm.startPrank(bridgeOwner);
        bridge.setPayMaster(_paymaster);
        vm.stopPrank();
    }

    function testSetRequiredBlockConfirmations(uint256 _blockConfirmations) public {
        vm.assume(_blockConfirmations > 0);
        vm.startPrank(bridgeOwner);
        bridge.setRequiredBlockConfirmations(_blockConfirmations);
        vm.stopPrank();
    }

    function setTrustedForwarder(address _trustedForwarder) public {
        vm.startPrank(bridgeOwner);
        bridge.setTrustedForwarder(_trustedForwarder);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SPECIAL STATES
    //////////////////////////////////////////////////////////////*/

    function testRefillBridge() public {
        uint256 initialBalance = dai.balanceOf(bridgeAddress);
        bridge.refillBridge();
        assertGt(dai.balanceOf(bridgeAddress), initialBalance);
    }
}
