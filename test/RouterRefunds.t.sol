// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchFixture} from "./helpers/LaunchFixture.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Deliberately claim-unaware test router. Models cash-only settlement and TAKE_ALL's
/// output-credit requirement; not an implementation of, or a dependency on, Universal Router.
contract CashDeltaRouter is IUnlockCallback {
    using SafeERC20 for IERC20;

    error DeltaNotPositive();
    IPoolManager internal immutable manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function swap(PoolKey memory key, SwapParams memory params, uint256 budget, bool requireOutputCredit)
        external
        returns (BalanceDelta delta)
    {
        IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(msg.sender, address(this), budget);
        IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(msg.sender, address(this), budget);
        delta = abi.decode(manager.unlock(abi.encode(key, params, requireOutputCredit)), (BalanceDelta));
        key.currency0.transfer(msg.sender, key.currency0.balanceOfSelf());
        key.currency1.transfer(msg.sender, key.currency1.balanceOfSelf());
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (PoolKey memory key, SwapParams memory params, bool requireOutputCredit) =
            abi.decode(data, (PoolKey, SwapParams, bool));
        BalanceDelta delta = manager.swap(key, params, "");
        if (requireOutputCredit && (params.zeroForOne ? delta.amount1() : delta.amount0()) < 0) {
            revert DeltaNotPositive();
        }
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta) private {
        if (delta < 0) {
            manager.sync(currency);
            currency.transfer(address(manager), uint256(-int256(delta)));
            manager.settle();
        } else if (delta > 0) {
            manager.take(currency, address(this), uint128(delta));
        }
    }
}

abstract contract RouterRefundCases is LaunchFixture {
    CashDeltaRouter internal cashRouter;

    function _setupRouters(bool lowerToken) internal {
        _setup(false, lowerToken, false);
        cashRouter = new CashDeltaRouter(manager);
        token.approve(address(cashRouter), type(uint256).max);
        IERC20(IMD).approve(address(cashRouter), type(uint256).max);
    }

    function test_partialSellCashDeltaCanBeNegativeUntilClaimsAreRedeemed() public {
        _compareRouters(false);
    }

    function test_partialBuyCashOnlySettlementLeavesRefundInRouter() public {
        _compareRouters(true);
    }

    function _compareRouters(bool buy) private {
        uint256 snapshot = vm.snapshotState();
        (BalanceDelta net, BalanceDelta raw, uint256 expectedFee) = _trade(buy, buy, 100_000 ether, true);
        uint256 expectedRefund = _refundClaims();
        assertGt(expectedRefund, 0);
        assertTrue(vm.revertToState(snapshot));

        uint256 cashBefore = IERC20(IMD).balanceOf(address(this));
        BalanceDelta cashDelta = cashRouter.swap(key, _params(buy, buy, 100_000 ether, true), BUDGET, false);
        uint256 refund = manager.balanceOf(address(cashRouter), uint160(IMD));
        assertEq(refund, expectedRefund);
        assertEq(hook.accruedFees(), expectedFee, "vault must receive only the actual-fill fee");
        assertEq(_launched(cashDelta), _launched(raw));
        assertEq(int256(IERC20(IMD).balanceOf(address(this))) - int256(cashBefore), _paired(cashDelta));
        assertEq(_paired(cashDelta) + int256(refund), _paired(net), "cash plus claims must conserve value");
        if (!buy) {
            assertLt(_paired(cashDelta), 0, "reproduce the reviewer's negative cash delta");
            assertGt(_paired(net), 0, "redeeming claims restores positive sell proceeds");
        }
    }

    function test_takeAllStyleRouterRevertsOnPartialSellDuringFeeWindow() public {
        SwapParams memory params = _params(false, false, 100_000 ether, true);
        vm.expectRevert(CashDeltaRouter.DeltaNotPositive.selector);
        cashRouter.swap(key, params, BUDGET, true);
        assertEq(hook.accruedFees(), 0);
        assertEq(manager.balanceOf(address(cashRouter), uint160(IMD)), 0);

        vm.roll(hook.openedBlock() + 10);
        BalanceDelta delta = cashRouter.swap(key, params, BUDGET, true);
        assertGt(_paired(delta), 0);
        assertEq(manager.balanceOf(address(cashRouter), uint160(IMD)), 0);
    }

    function test_claimAwarePartialSellNeedsNoIMDInputBudget() public {
        uint256 cashBefore = IERC20(IMD).balanceOf(address(this));
        BalanceDelta net =
            router.swap(key, _params(false, false, 100_000 ether, true), tokenIs0 ? BUDGET : 0, tokenIs0 ? 0 : BUDGET);
        assertGt(_paired(net), 0);
        assertEq(IERC20(IMD).balanceOf(address(this)) - cashBefore, uint256(_paired(net)));
        assertGt(_refundClaims(), 0);
        assertEq(manager.balanceOf(address(router), uint160(IMD)), 0);
        assertEq(IERC20(IMD).balanceOf(address(router)), 0);
    }

    function test_roundingKeepsDustFeesBelowRateAndRefundsExcess() public {
        (,, uint256 dustFee) = _trade(true, true, 3, false);
        assertEq(dustFee, 0);
        assertEq(_refundClaims(), 1);

        (, BalanceDelta raw, uint256 fee) = _trade(true, true, 10_000, false);
        assertEq(fee, 2307);
        assertEq(_refundClaims(), 1);
        uint256 numerator = uint256(-_paired(raw)) * 3000;
        assertLe(fee * 10_000, numerator, "fee must never exceed the rate on filled IMD");
        assertGt((fee + 1) * 10_000, numerator, "rounding may give at most one unit to the swapper");
        assertEq(manager.balanceOf(address(router), uint160(IMD)), 0, "dust refund must reach the user");
    }
}

contract RouterRefundToken0Test is RouterRefundCases {
    function setUp() public {
        _setupRouters(true);
    }
}

contract RouterRefundToken1Test is RouterRefundCases {
    function setUp() public {
        _setupRouters(false);
    }
}
