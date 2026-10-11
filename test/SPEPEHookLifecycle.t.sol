// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchFixture} from "./helpers/LaunchFixture.sol";
import {SPEPEHook} from "src/SPEPEHook.sol";
import {HookFlags} from "src/HookFlags.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

contract SPEPEHookLifecycleTest is LaunchFixture {
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    SPEPEHook internal unopened;
    PoolKey internal unopenedKey;

    function setUp() public {
        _setup(false, true, false);
        // A second hook on the same currencies has a distinct PoolId.
        unopened = _deployHook(manager, address(token));
        unopenedKey = key;
        unopenedKey.hooks = IHooks(address(unopened));
    }

    function test_constructorRejectsMissingManagerMissingTokenAndPairedToken() public {
        vm.expectRevert(SPEPEHook.InvalidDeployment.selector);
        new SPEPEHook(IPoolManager(address(0)), address(token));
        vm.expectRevert(SPEPEHook.InvalidDeployment.selector);
        new SPEPEHook(manager, address(0));
        vm.expectRevert(SPEPEHook.InvalidDeployment.selector);
        new SPEPEHook(manager, IMD);
    }

    function test_constructorRejectsMismatchedPermissionAddress() public {
        bytes memory creation = abi.encodePacked(type(SPEPEHook).creationCode, abi.encode(manager, address(token)));
        uint256 salt;
        address predicted = _predict(creation, bytes32(salt));
        while (HookFlags.matches(predicted, HookFlags.SPEPE_FLAGS)) {
            predicted = _predict(creation, bytes32(++salt));
        }
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, predicted));
        new SPEPEHook{salt: bytes32(salt)}(manager, address(token));
        assertEq(predicted.code.length, 0);
    }

    function test_preInitializationHasNoRunningWindowOrFees() public {
        uint256 openingBlock = vm.getBlockNumber() + 100_000;
        uint256 openingTime = vm.getBlockTimestamp() + 10 days;
        vm.roll(openingBlock);
        vm.warp(openingTime);
        _assertUnopened();
        assertEq(unopened.sweep(), 0);
        manager.initialize(unopenedKey, Q96);
        assertTrue(unopened.limitActive());
        assertEq(unopened.feeBps(), 3000);
        assertEq(unopened.openedAt(), openingTime);
        assertEq(unopened.openedBlock(), openingBlock);
    }

    /// Every invalid key is attempted on the real manager. Failure must not consume initialization.
    function test_invalidPoolTermsDoNotPoisonLaterInitialization() public {
        PoolKey memory invalid = unopenedKey;
        invalid.fee = 3000;
        _rejectPool(invalid);
        invalid = unopenedKey;
        invalid.fee = 0x800000; // Dynamic LP fees are explicitly forbidden for this launch.
        _rejectPool(invalid);
        invalid = unopenedKey;
        invalid.tickSpacing = 1;
        _rejectPool(invalid);
        invalid = unopenedKey;
        invalid.currency0 = Currency.wrap(address(1));
        _rejectPool(invalid);
        invalid = unopenedKey;
        invalid.currency1 = Currency.wrap(address(type(uint160).max));
        _rejectPool(invalid);

        manager.initialize(unopenedKey, Q96);
        assertTrue(unopened.initialized());
        assertEq(unopened.openedAt(), block.timestamp);
        assertEq(unopened.openedBlock(), block.number);
    }

    function test_wrongHookFieldRejectedEvenFromManager() public {
        PoolKey memory invalid = unopenedKey;
        invalid.hooks = IHooks(address(hook));
        vm.prank(address(manager));
        vm.expectRevert(SPEPEHook.InvalidPool.selector);
        unopened.beforeInitialize(address(this), invalid, Q96);
        _assertUnopened();
    }

    function test_coreInitializationFailureRollsBackHookClock() public {
        vm.expectRevert(abi.encodeWithSelector(TickMath.InvalidSqrtPrice.selector, uint160(0)));
        manager.initialize(unopenedKey, 0);
        _assertUnopened();
        uint256 openingTime = vm.getBlockTimestamp() + 123;
        uint256 openingBlock = vm.getBlockNumber() + 7;
        vm.warp(openingTime);
        vm.roll(openingBlock);
        manager.initialize(unopenedKey, Q96);
        assertEq(unopened.openedAt(), openingTime);
        assertEq(unopened.openedBlock(), openingBlock);
        assertEq(unopened.feeBps(), 3000);
    }

    function test_secondPoolCannotRestartExpiredWindows() public {
        vm.warp(hook.openedAt() + 3600);
        vm.roll(hook.openedBlock() + 10);
        PoolKey memory other = key;
        other.tickSpacing = 120;
        vm.expectRevert(
            _wrapped(address(hook), IHooks.beforeInitialize.selector, SPEPEHook.AlreadyInitialized.selector)
        );
        manager.initialize(other, Q96);
        assertFalse(hook.limitActive());
        assertEq(hook.feeBps(), 0);
        _trade(true, false, 10_000_001 ether, false);
    }

    function test_blockAndTimestampWindowsAreIndependent() public {
        vm.roll(hook.openedBlock() + 10);
        assertTrue(hook.limitActive());
        assertEq(hook.feeBps(), 0);
        SwapParams memory params = _params(true, false, 10_000_000 ether + 1, false);
        vm.expectRevert(_wrapped(address(hook), IHooks.afterSwap.selector, SPEPEHook.MaxBuyExceeded.selector));
        router.swap(key, params, BUDGET, BUDGET);
    }

    function test_expiredBuyWindowDoesNotDisableBlockBasedFee() public {
        vm.warp(hook.openedAt() + 3600);
        assertFalse(hook.limitActive());
        assertEq(hook.feeBps(), 3000);
        (,, uint256 fee) = _trade(true, false, 10_000_000 ether + 1, false);
        assertGt(fee, 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_callbacksRejectForgedSenderAndPayload(address caller, address sender, bytes32 payload) public {
        vm.assume(caller != address(manager));
        SwapParams memory params = _params(true, true, 100 ether, false);
        bytes memory data = abi.encode(payload, hook.vault());
        vm.startPrank(caller);
        vm.expectRevert(SPEPEHook.NotPoolManager.selector);
        unopened.beforeInitialize(sender, unopenedKey, Q96);
        vm.expectRevert(SPEPEHook.NotPoolManager.selector);
        hook.beforeSwap(sender, key, params, data);
        vm.expectRevert(SPEPEHook.NotPoolManager.selector);
        hook.afterSwap(sender, key, params, toBalanceDelta(-100 ether, 50 ether), data);
        vm.expectRevert(SPEPEHook.NotPoolManager.selector);
        hook.unlockCallback(data);
        vm.stopPrank();
        _assertUnopened();
        assertEq(hook.accruedFees(), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_beforeSwapNeverOverridesStaticFee(bool buy, bool exactInput, uint96 seed, uint8 offset) public {
        uint256 elapsed = bound(offset, 0, 20);
        vm.roll(hook.openedBlock() + elapsed);
        SwapParams memory params = _params(buy, exactInput, bound(seed, 1, 1_000_000 ether), false);
        vm.prank(address(manager));
        (bytes4 selector, BeforeSwapDelta delta, uint24 overrideFee) = hook.beforeSwap(address(this), key, params, "");
        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(overrideFee, 0);
        assertEq(delta.getUnspecifiedDelta(), 0);
        if (buy != exactInput || elapsed >= 10) assertEq(delta.getSpecifiedDelta(), 0);
    }

    function _rejectPool(PoolKey memory invalid) private {
        vm.expectRevert(_wrapped(address(unopened), IHooks.beforeInitialize.selector, SPEPEHook.InvalidPool.selector));
        manager.initialize(invalid, Q96);
        _assertUnopened();
    }

    function _assertUnopened() private view {
        assertFalse(unopened.initialized());
        assertFalse(unopened.limitActive());
        assertEq(unopened.feeBps(), 0);
        assertEq(unopened.openedAt(), 0);
        assertEq(unopened.openedBlock(), 0);
    }

    function _wrapped(address target, bytes4 callback, bytes4 reason) private pure returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            target,
            callback,
            abi.encodeWithSelector(reason),
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }
}
