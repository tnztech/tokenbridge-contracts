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
        uint256 initialInvested = bridge.investedAmount(address(dai));
        uint256 initialCollectable = bridge.interestAmount(address(dai));

        if (initialBalance < minCashThreshold) {
            bridge.refillBridge();

            uint256 afterBalance = dai.balanceOf(bridgeAddress);
            uint256 afterInvested = bridge.investedAmount(address(dai));
            uint256 afterCollectable = bridge.interestAmount(address(dai));

            assertLt(initialBalance, minCashThreshold);
            assertGe(afterBalance, initialBalance);
            assertLt(afterInvested, initialInvested);

            //Aproximately the same - slightly lower ue to ERC4626 math rounding
            assertLe(afterCollectable, initialCollectable);
            assertGt(afterCollectable, initialCollectable - 100);

            if (minCashThreshold > initialBalance + initialInvested) {
                assertLt(afterBalance, minCashThreshold);
                if (initialInvested > 0) {
                    assertGt(afterBalance, initialBalance);
                } else {
                    assertEq(afterBalance, initialBalance);
                }
            } else {
                //Aproximately the same - slightly off due to ERC4626 math rounding
                assertGt(afterBalance, minCashThreshold - 100);
                assertLe(afterBalance, minCashThreshold);
            }
        } else {
            vm.expectRevert(bytes("Bridge is Filled"));
            bridge.refillBridge();
        }
    }

    function testFuzzInvestDai(uint256 minCashThreshold, uint256 minInterestPaid) public {
        vm.assume(minCashThreshold > 1 ether);
        vm.assume(minInterestPaid > 1 ether);
        setMinCashThreshold(address(dai), minCashThreshold);
        setMinInterestPaid(address(dai), minInterestPaid);
        uint256 initialBalance = dai.balanceOf(bridgeAddress);
        uint256 initialInvested = bridge.investedAmount(address(dai));
        uint256 initialCollectable = bridge.interestAmount(address(dai));

        if (initialBalance > minCashThreshold) {
            bridge.investDai();

            uint256 afterBalance = dai.balanceOf(bridgeAddress);
            uint256 afterInvested = bridge.investedAmount(address(dai));
            uint256 afterCollectable = bridge.interestAmount(address(dai));

            assertLt(afterBalance, initialBalance);
            assertGt(afterInvested, initialInvested);
            //Aproximately the same - slightly lower ue to ERC4626 math rounding
            assertGt(afterCollectable, initialCollectable - 50);
            assertLt(afterCollectable, initialCollectable + 50);
        } else {
            vm.expectRevert(bytes("Balance too Low"));
            bridge.investDai();
        }
    }

    function testPayInterest(uint256 minCashThreshold, uint256 minInterestPaid) public {
        address token = address(dai);

        vm.assume(minCashThreshold > 100 ether);
        vm.assume(minInterestPaid > 100 ether);
        setMinCashThreshold(token, minCashThreshold);
        setMinInterestPaid(token, minInterestPaid);

        uint256 initialBalance = dai.balanceOf(bridgeAddress);
        uint256 initialInvested = bridge.investedAmount(token);
        uint256 initialCollectable = bridge.interestAmount(token);
        uint256 initialWithdrawable = bridge.previewWithdraw(token, initialCollectable);
        console.log("Bal:%e Inv:%e Col:%e", initialBalance, initialInvested, initialCollectable);
        if (initialCollectable >= minInterestPaid) {
            vm.expectEmit();
            emit UserRequestForAffirmation(gnosisInterestReceiver, initialCollectable);
            bridge.payInterest(token);

            uint256 afterBalance = dai.balanceOf(bridgeAddress);
            uint256 afterInvested = bridge.investedAmount(token);
            uint256 afterCollectable = bridge.interestAmount(token);
            uint256 afterWithdrawable = bridge.previewWithdraw(token, afterCollectable);
            assertGe(initialCollectable, initialWithdrawable);
            assertLt(afterCollectable, initialCollectable);
            assertLe(afterWithdrawable, initialWithdrawable);
            if (initialBalance >= minCashThreshold) {
                assertEq(afterBalance, initialBalance);
                assertGt(afterInvested, initialInvested);
                assertEq(afterInvested, initialInvested + initialCollectable);
            } else if (initialBalance + initialCollectable >= minCashThreshold) {
                assertGe(afterBalance, initialBalance);
                assertGe(afterInvested, initialInvested);
                if (minCashThreshold + initialCollectable - initialBalance >= bridge.minInterestPaid(token)) {
                    assertEq(afterInvested, initialInvested + initialCollectable + initialBalance - minCashThreshold);
                    assertEq(afterBalance - initialBalance, minCashThreshold - initialBalance);
                }
                else{
                    assertEq(afterInvested, initialInvested);
                }
            } else {
                assertGt(afterBalance, initialBalance);
                assertEq(afterBalance, initialBalance + initialCollectable);
                assertEq(afterInvested, initialInvested);
            }
            
        console.log("Bal:%e Inv:%e Col:%e", afterBalance, afterInvested, afterCollectable);
        console.log("initWith:%e afterWith:%e", initialWithdrawable, afterWithdrawable);
        } else {
            vm.expectRevert(bytes("Collectable interest too low"));
            bridge.payInterest(token);
        }
    }

    function testDisableInterest() public {
        address token = address(dai);
        skipTime(6 hours);
        uint256 initialBalance = dai.balanceOf(bridgeAddress);
        uint256 initialInvested = bridge.investedAmount(token);
        uint256 initialCollectable = bridge.interestAmount(token);
        uint256 initialWithdrawable = bridge.previewWithdraw(token, initialInvested);

        vm.startPrank(bridgeOwner);
        bridge.disableInterest(address(dai));
        vm.stopPrank();

        uint256 afterBalance = dai.balanceOf(bridgeAddress);
        uint256 afterInvested = bridge.investedAmount(token);
        uint256 afterCollectable = bridge.interestAmount(token);
        uint256 afterWithdrawable = bridge.previewWithdraw(token, afterInvested);
        if (initialInvested > 0) {
            assertGt(afterBalance, initialBalance);
            assertEq(afterBalance, initialBalance + initialInvested);
            assertLt(afterInvested, initialInvested);
            if (afterWithdrawable > 0) {
                assertLt(afterCollectable, afterWithdrawable);
            }
        } else {
            assertEq(afterBalance, initialBalance);
        }
        assertEq(afterInvested, 0);
        assertEq(afterWithdrawable, 0);
        assertGe(afterCollectable, afterWithdrawable);
        assertGe(initialInvested, initialWithdrawable);
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

    function initializeInterest(uint256 _minCashThreshold, uint256 _minInterestPaid) public {
        vm.startPrank(bridgeOwner);

        vm.expectRevert(bytes("Token not supported"));
        bridge.initializeInterest(address(sDAI), _minCashThreshold, _minInterestPaid, gnosisInterestReceiver);

        if (bridge.isInterestEnabled(address(dai)) == false) {
            bridge.initializeInterest(address(dai), _minCashThreshold, _minInterestPaid, gnosisInterestReceiver);
        } else {
            vm.expectRevert(bytes("Interest already enabled"));
            bridge.initializeInterest(address(dai), _minCashThreshold, _minInterestPaid, gnosisInterestReceiver);
        }

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
        uint256 initialInvested = bridge.investedAmount(address(dai));
        uint256 initialCollectable = bridge.interestAmount(address(dai));

        // config change to force valid refill state
        vm.prank(bridgeOwner);
        bridge.setMinCashThreshold(address(dai), initialBalance + 1000 ether);
        //refill
        bridge.refillBridge();

        uint256 afterBalance = dai.balanceOf(bridgeAddress);
        uint256 afterInvested = bridge.investedAmount(address(dai));
        uint256 afterCollectable = bridge.interestAmount(address(dai));

        assertEq(afterBalance, initialBalance + 1000 ether);
    }
    
    function testPayInterestAndThenInvest(uint256 minCashThreshold) public {

        vm.assume(minCashThreshold > 100 ether);
        setMinCashThreshold(address(dai), minCashThreshold);

        uint256 initialBalance = dai.balanceOf(bridgeAddress);
        uint256 initialInvested = bridge.investedAmount(address(dai));
        uint256 initialCollectable = bridge.interestAmount(address(dai));

        assertGt(initialCollectable, bridge.minInterestPaid(address(dai)));
        bridge.payInterest(address(dai));
        uint256 duringBalance = dai.balanceOf(bridgeAddress);
        uint256 duringInvested = bridge.investedAmount(address(dai));
        assertEq(initialCollectable, duringBalance - initialBalance + duringInvested - initialInvested);
        if (duringBalance > bridge.minCashThreshold(address(dai))){
            bridge.investDai();
        }
        else{
            vm.expectRevert("Balance too Low");
            bridge.investDai();
        }


        uint256 afterBalance = dai.balanceOf(bridgeAddress);
        uint256 afterInvested = bridge.investedAmount(address(dai));
        uint256 afterCollectable = bridge.interestAmount(address(dai));
        if (initialBalance >= bridge.minCashThreshold(address(dai))) {
            assertGe(initialBalance, afterBalance);
        } else {
            assertLt(initialBalance, afterBalance);
        }
        assertGe(afterInvested, initialInvested);
        assertEq(afterCollectable, 0);
    }
    
}
