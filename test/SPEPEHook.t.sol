// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchFixture} from "./helpers/LaunchFixture.sol";
import {SPEPEHook} from "../src/SPEPEHook.sol";
import {SPEPE} from "../src/SPEPE.sol";
import {HookFlags} from "../src/HookFlags.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract SwapCases is LaunchFixture {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    function test_exactInputBuy() public {
        _trade(true, true, 1_000 ether, false);
    }

    function test_exactOutputBuy() public {
        (BalanceDelta net,,) = _trade(true, false, 1_000 ether, false);
        assertEq(_launched(net), 1_000 ether);
    }

    function test_exactInputSell() public {
        _trade(false, true, 1_000 ether, false);
    }

    function test_exactOutputSell() public {
        (BalanceDelta net,,) = _trade(false, false, 1_000 ether, false);
        assertApproxEqAbs(_paired(net), int256(1_000 ether), 1);
    }

    function test_partialExactInputBuyRefundsClaims() public {
        (BalanceDelta net,,) = _trade(true, true, 1_000_000 ether, true);
        assertLt(uint256(-_paired(net)), 1_000_000 ether);
        assertGt(_refundClaims(), 0);
    }

    function test_partialExactOutputSellRefundsClaims() public {
        (BalanceDelta net,,) = _trade(false, false, 1_000_000 ether, true);
        assertLt(uint256(_paired(net)), 1_000_000 ether);
        assertGt(_refundClaims(), 0);
    }

    function test_partialExactOutputBuy() public {
        (BalanceDelta net,,) = _trade(true, false, 1_000_000 ether, true);
        assertLt(uint256(_launched(net)), 1_000_000 ether);
        assertEq(_refundClaims(), 0);
    }

    function test_partialExactInputSell() public {
        (BalanceDelta net,,) = _trade(false, true, 1_000_000 ether, true);
        assertLt(uint256(-_launched(net)), 1_000_000 ether);
        assertEq(_refundClaims(), 0);
    }

    function test_feeDecayEveryBlockAndBoundary() public {
        uint256 start = hook.openedBlock();
        for (uint256 i; i <= 11; ++i) {
            vm.roll(start + i);
            assertEq(hook.feeBps(), i < 10 ? 3000 - 300 * i : 0);
            _trade(true, true, 100 ether, false);
            _trade(false, false, 100 ether, false);
        }
    }

    function test_limitUsesActualPartialBuyNotRequest() public {
        (BalanceDelta net,,) = _trade(true, false, 50_000_000 ether, true);
        assertGt(_launched(net), 0);
        assertLe(uint256(_launched(net)), hook.maxBuy());
    }

    function test_maxBuyExactBoundaryAndOneWeiAbove() public {
        uint256 cap = hook.maxBuy();
        assertEq(cap, 10_000_000 ether);
        _trade(true, false, cap, false);
        SwapParams memory params = _params(true, false, cap + 1, false);
        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, SPEPEHook.MaxBuyExceeded.selector));
        router.swap(key, params, BUDGET, BUDGET);
    }

    function test_overLimitExactInputBuyReverts() public {
        SwapParams memory params = _params(true, true, 30_000_000 ether, false);
        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, SPEPEHook.MaxBuyExceeded.selector));
        router.swap(key, params, BUDGET, BUDGET);
    }

    function test_rejectedBuyRollsBackPriceBalancesAndClaims() public {
        _trade(false, true, 1_000 ether, false);
        (uint160 priceBefore,,,) = manager.getSlot0(key.toId());
        uint256 feesBefore = hook.accruedFees();
        uint256 tokenBefore = token.balanceOf(address(this));
        uint256 pairBefore = IERC20(IMD).balanceOf(address(this));
        uint256 managerTokenBefore = token.balanceOf(address(manager));
        uint256 managerPairBefore = IERC20(IMD).balanceOf(address(manager));
        SwapParams memory params = _params(true, false, hook.maxBuy() + 1, false);

        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, SPEPEHook.MaxBuyExceeded.selector));
        router.swap(key, params, BUDGET, BUDGET);

        (uint160 priceAfter,,,) = manager.getSlot0(key.toId());
        assertEq(priceAfter, priceBefore);
        assertEq(hook.accruedFees(), feesBefore);
        assertEq(token.balanceOf(address(this)), tokenBefore);
        assertEq(IERC20(IMD).balanceOf(address(this)), pairBefore);
        assertEq(token.balanceOf(address(manager)), managerTokenBefore);
        assertEq(IERC20(IMD).balanceOf(address(manager)), managerPairBefore);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(IERC20(IMD).balanceOf(address(router)), 0);
        assertEq(manager.balanceOf(address(router), uint160(IMD)), 0);
        assertEq(manager.currencyDelta(address(hook), Currency.wrap(IMD)), 0);
        assertEq(manager.getNonzeroDeltaCount(), 0);

        // A rejected buy does not leave the pool locked or poison subsequent swaps.
        _trade(true, false, 1_000 ether, false);
    }

    function test_limitExpiresAtExactlyOneHour() public {
        vm.warp(hook.openedAt() + 3599);
        assertTrue(hook.limitActive());
        SwapParams memory params = _params(true, false, hook.maxBuy() + 1, false);
        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, SPEPEHook.MaxBuyExceeded.selector));
        router.swap(key, params, BUDGET, BUDGET);
        vm.warp(hook.openedAt() + 3600);
        assertFalse(hook.limitActive());
        _trade(true, false, hook.maxBuy() + 1, false);
    }

    function test_largeSellsAreNeverLimited() public {
        (BalanceDelta net,,) = _trade(false, true, 20_000_000 ether, false);
        assertEq(_launched(net), -int256(20_000_000 ether));
    }

    function test_repeatedBuysArePerSwapNotPerRouter() public {
        _trade(true, false, 6_000_000 ether, false);
        _trade(true, false, 6_000_000 ether, false);
        _trade(true, false, 6_000_000 ether, false);
    }

    function test_anyoneSweepsOnlyToFixedVault() public {
        _trade(true, false, 1_000 ether, false);
        _trade(false, true, 1_000 ether, false);
        uint256 fee = hook.accruedFees();
        uint256 vaultBefore = IERC20(IMD).balanceOf(hook.vault());
        address stranger = makeAddr("sweeper");
        vm.prank(stranger);
        assertEq(hook.sweep(), fee);
        assertEq(IERC20(IMD).balanceOf(hook.vault()) - vaultBefore, fee);
        assertEq(IERC20(IMD).balanceOf(stranger), 0);
        assertEq(hook.accruedFees(), 0);
        assertEq(hook.sweep(), 0);
        _trade(true, true, 1_000 ether, false);
        assertGt(hook.accruedFees(), 0);
    }

    function test_hugeRequestsCanPartiallyFillAllFourModes() public {
        _trade(true, true, 1 << 200, true);
        _trade(true, false, 1 << 200, true);
        _trade(false, true, 1 << 200, true);
        _trade(false, false, 1 << 200, true);
    }

    function test_nearInt256MaxExactOutputCanPartiallyFill() public {
        // Only the capped reservation is added to amountSpecified by PoolManager.
        // Its sum fits int256 even though grossing up the unfilled request would not.
        for (uint256 offset; offset <= 10; ++offset) {
            vm.roll(hook.openedBlock() + offset);
            uint256 rate = offset < 10 ? 3_000 - 300 * offset : 0;
            uint256 largestReserve = (uint256(1) << 127) * rate / 10_000;
            uint256 largestRequest = uint256(type(int256).max) - largestReserve;
            _trade(false, false, largestRequest, true);
            if (rate == 0) {
                assertEq(_refundClaims(), 0);
            } else {
                assertGt(_refundClaims(), 0);
                SwapParams memory params = _params(false, false, largestRequest + 1, true);
                vm.expectRevert(_wrapped(IHooks.beforeSwap.selector, SPEPEHook.UnrepresentableFee.selector));
                router.swap(key, params, BUDGET, BUDGET);
            }
        }
    }

    function test_unrepresentableExactOutputFeeHasExplicitError() public {
        SwapParams memory params = _params(false, false, uint256(type(int256).max), true);
        vm.expectRevert(_wrapped(IHooks.beforeSwap.selector, SPEPEHook.UnrepresentableFee.selector));
        router.swap(key, params, BUDGET, BUDGET);
    }

    function test_int256MinExactInputCanPartiallyFill() public {
        SwapParams memory params = _params(true, true, 1, true);
        params.amountSpecified = type(int256).min;
        BalanceDelta net = router.swap(key, params, BUDGET, BUDGET);
        assertGt(_launched(net), 0);
        assertGt(hook.accruedFees(), 0);
    }

    function test_oneWeiInputIsFullyRefundedAsClaim() public {
        (,, uint256 fee) = _trade(true, true, 1, false);
        assertEq(fee, 0);
        assertEq(hook.accruedFees(), 0);
        assertEq(_refundClaims(), 1);
    }

    function test_emptyLiquidityRefundsAllReservationsInEveryMode() public {
        router.liquidity(key, ModifyLiquidityParams(-887220, 887220, -int256(400_000_000 ether), bytes32(0)), 0, 0);
        for (uint256 mode; mode < 4; ++mode) {
            bool buy = mode < 2;
            bool exactInput = mode % 2 == 0;
            (BalanceDelta net, BalanceDelta raw, uint256 fee) = _trade(buy, exactInput, 1_000 ether, true);
            assertEq(BalanceDelta.unwrap(raw), 0, "empty pool unexpectedly filled");
            assertEq(BalanceDelta.unwrap(net), 0, "zero fill cost the swapper tokens");
            assertEq(fee, 0);
            if (buy == exactInput) assertGt(_refundClaims(), 0, "reservation not returned");
            else assertEq(_refundClaims(), 0);
        }
        assertEq(hook.accruedFees(), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_largePriceLimitedRequests(bool buy, bool exactInput, uint256 seed, uint8 offset) public virtual {
        vm.roll(hook.openedBlock() + bound(offset, 0, 10));
        // Leave room for the largest capped reservation at every fee rate.
        // These requests vastly exceed the actual fill: exercise the capped reserve, not liquidity.
        uint256 amount = bound(seed, 1e30, uint256(type(int256).max) - (uint256(1) << 127));
        (BalanceDelta net,,) = _trade(buy, exactInput, amount, true);
        assertTrue(BalanceDelta.unwrap(net) != 0, "expected a real partial fill");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_actualFillFees(bool buy, bool exactInput, bool priceLimited, uint96 amount, uint8 offset)
        public
        virtual
    {
        vm.roll(hook.openedBlock() + bound(offset, 0, 12));
        _trade(buy, exactInput, bound(amount, 1 ether, 1_000_000 ether), priceLimited);
    }

    function _wrapped(bytes4 callback, bytes4 reason) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hook),
            callback,
            abi.encodeWithSelector(reason),
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }
}

contract SPEPEHookToken0Test is SwapCases {
    using StateLibrary for IPoolManager;

    function setUp() public {
        _setup(false, true, false);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_largePriceLimitedRequests(bool buy, bool exactInput, uint256 seed, uint8 offset) public override {
        super.testFuzz_largePriceLimitedRequests(buy, exactInput, seed, offset);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_actualFillFees(bool buy, bool exactInput, bool priceLimited, uint96 amount, uint8 offset)
        public
        override
    {
        super.testFuzz_actualFillFees(buy, exactInput, priceLimited, amount, offset);
    }

    function test_permissionsAndCreate2AddressMatch() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(
            p.beforeInitialize && p.beforeSwap && p.afterSwap && p.beforeSwapReturnDelta && p.afterSwapReturnDelta
        );
        assertFalse(
            p.afterInitialize || p.beforeAddLiquidity || p.afterAddLiquidity || p.beforeRemoveLiquidity
                || p.afterRemoveLiquidity || p.beforeDonate || p.afterDonate || p.afterAddLiquidityReturnDelta
                || p.afterRemoveLiquidityReturnDelta
        );
        assertEq(HookFlags.flagsOf(address(hook)), 0x20cc);
        assertEq(address(hook.poolManager()), address(manager));
        assertEq(hook.token(), address(token));
        assertEq(hook.vault(), 0x3dD5F73dD1A4E62630fAd3909673F130aD429985);
    }

    function test_allEnabledCallbacksRejectNonManager() public {
        SwapParams memory params = _params(true, true, 1 ether, false);
        vm.expectRevert(SPEPEHook.NotPoolManager.selector);
        hook.beforeInitialize(address(this), key, Q96);
        vm.expectRevert(SPEPEHook.NotPoolManager.selector);
        hook.beforeSwap(address(this), key, params, "");
        vm.expectRevert(SPEPEHook.NotPoolManager.selector);
        hook.afterSwap(address(this), key, params, toBalanceDelta(0, 0), "");
        vm.expectRevert(SPEPEHook.NotPoolManager.selector);
        hook.unlockCallback("");
    }

    function test_initializationRejectsOtherPoolAndCannotResetClock() public {
        SPEPEHook fresh = _deployHook(manager, address(new SPEPE()));
        PoolKey memory other = key;
        other.hooks = IHooks(address(fresh));
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(fresh),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(SPEPEHook.InvalidPool.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(other, Q96);
        uint256 opened = hook.openedAt();
        vm.warp(opened + 4000);
        vm.prank(address(manager));
        vm.expectRevert(SPEPEHook.AlreadyInitialized.selector);
        hook.beforeInitialize(address(this), key, Q96);
        assertEq(hook.openedAt(), opened);
    }

    function test_noEscapesAndWithinDeploymentSizeLimits() public view {
        assertLe(type(SPEPEHook).creationCode.length + 64, 49_152);
        assertLe(address(hook).code.length, 24_576);
        _scan(address(hook).code);
        _scan(address(token).code);
    }

    function _scan(bytes memory code) private pure {
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) i += op - 0x5f;
            else require(op != 0xff && op != 0xf4 && op != 0xf2, "escape opcode");
        }
    }
}

contract SPEPEHookToken1Test is SwapCases {
    function setUp() public {
        _setup(false, false, false);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_largePriceLimitedRequests(bool buy, bool exactInput, uint256 seed, uint8 offset) public override {
        super.testFuzz_largePriceLimitedRequests(buy, exactInput, seed, offset);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_actualFillFees(bool buy, bool exactInput, bool priceLimited, uint96 amount, uint8 offset)
        public
        override
    {
        super.testFuzz_actualFillFees(buy, exactInput, priceLimited, amount, offset);
    }
}

contract SPEPEFreshManagerTest is LaunchFixture {
    function setUp() public {
        _setup(false, true, true);
    }

    function test_buyCollectsClaimsWithNoPairedReservesBeforeSettlement() public {
        assertEq(IERC20(IMD).balanceOf(address(manager)), 0);
        _trade(true, false, 1_000 ether, false);
        assertGt(hook.accruedFees(), 0);
        hook.sweep();
        assertEq(hook.accruedFees(), 0);
    }
}
