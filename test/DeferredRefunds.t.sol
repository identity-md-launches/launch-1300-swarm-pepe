// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {LaunchFixture} from "./helpers/LaunchFixture.sol";
import {DeferredRefundRouter} from "./helpers/DeferredRefundRouter.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract DeferredRefundCases is LaunchFixture {
    using TransientStateLibrary for IPoolManager;

    DeferredRefundRouter internal deferred;

    function _setupDeferred(bool fork, bool lowerToken) internal {
        _setup(fork, lowerToken, false);
        deferred = new DeferredRefundRouter(manager);
        token.approve(address(deferred), type(uint256).max);
        IERC20(IMD).approve(address(deferred), type(uint256).max);
        manager.setOperator(address(deferred), true);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_cashPlusDeferredClaimsEqualsActualFillLessFee(
        bool buy,
        bool exactInput,
        bool priceLimited,
        uint96 seed,
        uint8 blockOffset,
        bytes32 hookData
    ) public virtual {
        vm.roll(hook.openedBlock() + bound(blockOffset, 0, 12));
        uint256 amount = bound(seed, 1, 1_000_000 ether);
        (uint256 refund,) = _deferredTrade(buy, exactInput, amount, priceLimited, abi.encode(hookData));
        uint256 beforeRedemption = IERC20(IMD).balanceOf(address(this));
        deferred.redeem(Currency.wrap(IMD), refund);
        assertEq(IERC20(IMD).balanceOf(address(this)), beforeRedemption + refund);
        assertEq(manager.balanceOf(address(this), uint160(IMD)), 0);
        _assertSettled();
    }

    function test_dustRoundingInAllFourModes() public {
        uint256[8] memory amounts = [uint256(1), 2, 3, 4, 9, 10, 11, 100];
        for (uint256 mode; mode < 4; ++mode) {
            for (uint256 i; i < amounts.length; ++i) {
                _deferredTrade(mode < 2, mode % 2 == 0, amounts[i], false, "");
            }
        }
        uint256 refund = manager.balanceOf(address(this), uint160(IMD));
        uint256 balance = IERC20(IMD).balanceOf(address(this));
        deferred.redeem(Currency.wrap(IMD), refund);
        assertEq(IERC20(IMD).balanceOf(address(this)), balance + refund);
    }

    function test_sweepCannotConsumeDeferredRefundsAndRefundsSurviveExpiry() public {
        (uint256 buyRefund,) = _deferredTrade(true, true, 1_000_000 ether, true, "");
        (uint256 sellRefund,) = _deferredTrade(false, false, 1_000_000 ether, true, "");
        assertGt(buyRefund, 0);
        assertGt(sellRefund, 0);
        uint256 refundable = buyRefund + sellRefund;
        uint256 fees = hook.accruedFees();
        uint256 vaultBefore = IERC20(IMD).balanceOf(hook.vault());
        vm.prank(makeAddr("unrelated sweeper"));
        assertEq(hook.sweep(), fees);
        assertEq(IERC20(IMD).balanceOf(hook.vault()), vaultBefore + fees);
        assertEq(manager.balanceOf(address(this), uint160(IMD)), refundable);
        assertEq(hook.accruedFees(), 0);

        vm.roll(hook.openedBlock() + 100);
        vm.warp(hook.openedAt() + 2 hours);
        uint256 beforeRedemption = IERC20(IMD).balanceOf(address(this));
        deferred.redeem(Currency.wrap(IMD), refundable);
        assertEq(IERC20(IMD).balanceOf(address(this)), beforeRedemption + refundable);
        assertEq(manager.balanceOf(address(this), uint160(IMD)), 0);
        assertEq(IERC20(IMD).balanceOf(hook.vault()), vaultBefore + fees);
        assertEq(hook.sweep(), 0);
        _assertSettled();
    }

    function test_claimsAreTransferableButCannotBeRedeemedTwice() public {
        (uint256 refund,) = _deferredTrade(true, true, 1_000_000 ether, true, "");
        address recipient = makeAddr("refund recipient");
        assertGt(refund, 0);
        manager.transfer(recipient, uint160(IMD), refund);
        assertEq(manager.balanceOf(address(this), uint160(IMD)), 0);
        uint256 fees = hook.accruedFees();
        uint256 recipientBefore = IERC20(IMD).balanceOf(recipient);
        vm.startPrank(recipient);
        manager.setOperator(address(deferred), true);
        deferred.redeem(Currency.wrap(IMD), refund);
        vm.expectRevert(); // The underlying ERC-6909 rejects spending an exhausted balance.
        deferred.redeem(Currency.wrap(IMD), refund);
        vm.stopPrank();
        assertEq(IERC20(IMD).balanceOf(recipient), recipientBefore + refund);
        assertEq(hook.accruedFees(), fees);
        _assertSettled();
    }

    function test_hookDataCannotRedirectOrWaiveFeeOrRefund() public {
        address attacker = makeAddr("hookData beneficiary");
        (uint256 refund, uint256 fee) =
            _deferredTrade(true, true, 1_000_000 ether, true, abi.encode(attacker, uint256(0), true));
        assertGt(refund, 0);
        assertGt(fee, 0);
        assertEq(manager.balanceOf(attacker, uint160(IMD)), 0);
        assertEq(IERC20(IMD).balanceOf(attacker), 0);
        assertEq(manager.balanceOf(address(this), uint160(IMD)), refund);
        vm.startPrank(attacker);
        vm.expectRevert();
        manager.transferFrom(address(this), attacker, uint160(IMD), refund);
        vm.expectRevert();
        manager.transferFrom(address(hook), attacker, uint160(IMD), fee);
        vm.stopPrank();
        assertEq(hook.accruedFees(), fee);
    }

    function test_zeroFillRefundIsRedeemableAfterLiquidityWasRemoved() public {
        router.liquidity(key, ModifyLiquidityParams(-887220, 887220, -int256(400_000_000 ether), bytes32(0)), 0, 0);
        uint256 beforePair = IERC20(IMD).balanceOf(address(this));
        uint256 beforeToken = token.balanceOf(address(this));
        (uint256 first,) = _deferredTrade(true, true, 1_000_000 ether, true, "");
        (uint256 second,) = _deferredTrade(false, false, 1_000_000 ether, true, "");
        assertGt(first, 0);
        assertGt(second, 0);
        deferred.redeem(Currency.wrap(IMD), first + second);
        assertEq(IERC20(IMD).balanceOf(address(this)), beforePair);
        assertEq(token.balanceOf(address(this)), beforeToken);
        assertEq(hook.accruedFees(), 0);
        _assertSettled();
    }

    function _deferredTrade(bool buy, bool exactInput, uint256 amount, bool priceLimited, bytes memory hookData)
        internal
        returns (uint256 refund, uint256 fee)
    {
        uint256 pairBefore = IERC20(IMD).balanceOf(address(this));
        uint256 tokenBefore = token.balanceOf(address(this));
        uint256 claimsBefore = manager.balanceOf(address(this), uint160(IMD));
        uint256 feesBefore = hook.accruedFees();
        vm.recordLogs();
        (BalanceDelta cash, uint256 c0, uint256 c1) =
            deferred.swap(key, _params(buy, exactInput, amount, priceLimited), BUDGET, hookData);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        BalanceDelta raw;
        uint256 swapCount;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(manager) && logs[i].topics.length > 0
                    && logs[i].topics[0]
                        == keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
            ) {
                (int128 a, int128 b,,,, uint24 lpFee) =
                    abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                raw = toBalanceDelta(a, b);
                assertEq(lpFee, 12_500);
                ++swapCount;
            }
        }
        assertEq(swapCount, 1, "fee collection must not execute another pool swap");
        refund = tokenIs0 ? c1 : c0;
        assertEq(tokenIs0 ? c0 : c1, 0, "SPEPE claim minted");
        fee = hook.accruedFees() - feesBefore;
        int256 paired = _paired(raw);
        uint256 gross = uint256(paired < 0 ? -paired : paired);
        uint256 elapsed = block.number - hook.openedBlock();
        uint256 rate = elapsed < 10 ? 3000 - 300 * elapsed : 0;
        assertEq(fee, gross * rate / 10_000, "fee must use the actual fill");
        uint256 accrualEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(hook) && logs[i].topics.length > 0
                    && logs[i].topics[0] == keccak256("FeeAccrued(address,uint256,uint256,uint256)")
            ) {
                assertEq(
                    logs[i].topics[1], bytes32(uint256(uint160(address(deferred)))), "event must identify the router"
                );
                (uint256 loggedFill, uint256 loggedFee, uint256 loggedRefund) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256));
                assertEq(loggedFill, gross);
                assertEq(loggedFee, fee);
                assertEq(loggedRefund, refund);
                ++accrualEvents;
            }
        }
        assertEq(accrualEvents, rate == 0 ? 0 : 1);
        assertEq(_paired(cash) + int256(refund), paired - int256(fee), "cash and claim do not conserve IMD");
        assertEq(_launched(cash), _launched(raw), "SPEPE charged as fee");
        assertEq(int256(IERC20(IMD).balanceOf(address(this))) - int256(pairBefore), _paired(cash));
        assertEq(int256(token.balanceOf(address(this))) - int256(tokenBefore), _launched(cash));
        assertEq(manager.balanceOf(address(this), uint160(IMD)), claimsBefore + refund);
        if (buy != exactInput || rate == 0) assertEq(refund, 0);
        if (exactInput) {
            uint256 spent = uint256(-(buy ? paired - int256(fee) : _launched(raw)));
            assertLe(spent, amount, "net exact input exceeded the request");
        } else {
            int256 received = buy ? _launched(raw) : paired - int256(fee);
            assertGe(received, 0);
            assertLe(uint256(received), amount + 1, "exact output overcharged");
            if (!priceLimited) assertGe(uint256(received), amount, "full exact output underdelivered");
        }
        _assertSettled();
    }

    function _assertSettled() internal view {
        assertEq(manager.getNonzeroDeltaCount(), 0);
        assertEq(manager.currencyDelta(address(hook), Currency.wrap(IMD)), 0);
        assertEq(manager.balanceOf(address(deferred), uint160(IMD)), 0);
        assertEq(manager.balanceOf(address(deferred), uint160(address(token))), 0);
        assertEq(token.balanceOf(address(deferred)), 0);
        assertEq(IERC20(IMD).balanceOf(address(deferred)), 0);
        assertEq(token.balanceOf(address(hook)), 0);
        assertEq(IERC20(IMD).balanceOf(address(hook)), 0);
    }
}

contract DeferredRefundToken0Test is DeferredRefundCases {
    function setUp() public {
        _setupDeferred(false, true);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_cashPlusDeferredClaimsEqualsActualFillLessFee(
        bool buy,
        bool exactInput,
        bool priceLimited,
        uint96 seed,
        uint8 blockOffset,
        bytes32 hookData
    ) public override {
        super.testFuzz_cashPlusDeferredClaimsEqualsActualFillLessFee(
            buy, exactInput, priceLimited, seed, blockOffset, hookData
        );
    }
}

contract DeferredRefundToken1Test is DeferredRefundCases {
    function setUp() public {
        _setupDeferred(false, false);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_cashPlusDeferredClaimsEqualsActualFillLessFee(
        bool buy,
        bool exactInput,
        bool priceLimited,
        uint96 seed,
        uint8 blockOffset,
        bytes32 hookData
    ) public override {
        super.testFuzz_cashPlusDeferredClaimsEqualsActualFillLessFee(
            buy, exactInput, priceLimited, seed, blockOffset, hookData
        );
    }
}

/// @dev CLI-selected Robinhood forks only. An absent fork is explicitly skipped in offline verification.
contract DeferredRefundRobinhoodForkTest is DeferredRefundCases {
    function setUp() public {
        try vm.activeFork() returns (uint256) {}
        catch {
            vm.skip(true);
            return;
        }
        assertEq(block.chainid, 4663);
        assertEq(IERC20Metadata(IMD).symbol(), "IMD");
        assertEq(IERC20Metadata(IMD).decimals(), 18);
        _setupDeferred(true, true);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_cashPlusDeferredClaimsEqualsActualFillLessFee(
        bool buy,
        bool exactInput,
        bool priceLimited,
        uint96 seed,
        uint8 blockOffset,
        bytes32 hookData
    ) public override {
        super.testFuzz_cashPlusDeferredClaimsEqualsActualFillLessFee(
            buy, exactInput, priceLimited, seed, blockOffset, hookData
        );
    }
}
