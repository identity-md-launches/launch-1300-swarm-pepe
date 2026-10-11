// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LaunchFixture} from "./helpers/LaunchFixture.sol";
import {DeferredRefundRouter} from "./helpers/DeferredRefundRouter.sol";
import {SPEPEHook} from "src/SPEPEHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Ghost accounting comes from PoolManager Swap events, not the hook's fee event or quote.
contract DeferredRefundHandler is Test {
    using StateLibrary for IPoolManager;

    SPEPEHook public immutable hook;
    IPoolManager public immutable manager;
    DeferredRefundRouter public immutable router;
    IERC20 public immutable token;
    IERC20 public immutable pair;
    PoolKey internal key;
    bool internal immutable tokenIs0;
    address[3] public actors;
    uint256 public feesProduced;
    uint256 public feesSwept;
    uint256 public refundsProduced;
    uint256 public refundsRedeemed;
    uint256 public successfulSwaps;
    uint256 public rejectedBuys;

    constructor(SPEPEHook h, DeferredRefundRouter r, PoolKey memory k, address[3] memory users) {
        hook = h;
        manager = h.poolManager();
        router = r;
        token = IERC20(h.token());
        pair = IERC20(h.PAIRED_CURRENCY());
        key = k;
        tokenIs0 = Currency.unwrap(k.currency0) == h.token();
        actors = users;
        for (uint256 i; i < users.length; ++i) {
            vm.startPrank(users[i]);
            token.approve(address(r), type(uint256).max);
            pair.approve(address(r), type(uint256).max);
            manager.setOperator(address(r), true);
            vm.stopPrank();
        }
    }

    function trade(uint256 actorSeed, uint96 amountSeed, bool buy, bool exactInput, bool priceLimited) external {
        address actor = actors[actorSeed % actors.length];
        uint256 amount = bound(amountSeed, 1, 500_000 ether);
        SwapParams memory params = _params(buy, exactInput, amount, priceLimited);
        uint256 beforePair = pair.balanceOf(actor);
        uint256 beforeToken = token.balanceOf(actor);
        uint256 beforeFees = hook.accruedFees();
        uint256 beforeClaims = manager.balanceOf(actor, uint160(address(pair)));
        vm.recordLogs();
        vm.prank(actor);
        (BalanceDelta cash, uint256 claims0, uint256 claims1) =
            router.swap(key, params, 2_000_000 ether, abi.encode(actorSeed));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        int256 rawPair;
        int256 rawToken;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(manager) && logs[i].topics.length > 0
                    && logs[i].topics[0]
                        == keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
            ) {
                (int128 a, int128 b,,,, uint24 lpFee) =
                    abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                rawPair = tokenIs0 ? int256(b) : int256(a);
                rawToken = tokenIs0 ? int256(a) : int256(b);
                assertEq(lpFee, 12_500);
                ++count;
            }
        }
        assertEq(count, 1);
        uint256 elapsed = block.number - hook.openedBlock();
        uint256 rate = elapsed < 10 ? 3000 - 300 * elapsed : 0;
        uint256 filled = uint256(rawPair < 0 ? -rawPair : rawPair);
        uint256 expectedFee = filled * rate / 10_000;
        uint256 refund = tokenIs0 ? claims1 : claims0;
        int256 cashPair = tokenIs0 ? int256(cash.amount1()) : int256(cash.amount0());
        int256 cashToken = tokenIs0 ? int256(cash.amount0()) : int256(cash.amount1());
        assertEq(tokenIs0 ? claims0 : claims1, 0);
        assertEq(cashPair + int256(refund), rawPair - int256(expectedFee));
        assertEq(cashToken, rawToken);
        assertEq(int256(pair.balanceOf(actor)) - int256(beforePair), cashPair);
        assertEq(int256(token.balanceOf(actor)) - int256(beforeToken), cashToken);
        assertEq(hook.accruedFees() - beforeFees, expectedFee);
        assertEq(manager.balanceOf(actor, uint160(address(pair))) - beforeClaims, refund);
        if (block.timestamp < hook.openedAt() + 3600 && rawToken > 0) assertLe(uint256(rawToken), 1e25);
        if (rate == 0) assertEq(refund, 0);
        feesProduced += expectedFee;
        refundsProduced += refund;
        ++successfulSwaps;
    }

    function redeem(uint256 actorSeed, uint256 amountSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 claims = manager.balanceOf(actor, uint160(address(pair)));
        if (claims == 0) return;
        uint256 amount = bound(amountSeed, 1, claims);
        uint256 beforePair = pair.balanceOf(actor);
        vm.prank(actor);
        router.redeem(Currency.wrap(address(pair)), amount);
        assertEq(pair.balanceOf(actor), beforePair + amount);
        refundsRedeemed += amount;
    }

    function transferRefund(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = manager.balanceOf(from, uint160(address(pair)));
        if (balance == 0) return;
        vm.prank(from);
        manager.transfer(to, uint160(address(pair)), bound(amountSeed, 1, balance));
    }

    function sweep(uint256 actorSeed) external {
        uint256 owed = hook.accruedFees();
        uint256 vaultBefore = pair.balanceOf(hook.vault());
        vm.prank(actors[actorSeed % actors.length]);
        assertEq(hook.sweep(), owed);
        assertEq(pair.balanceOf(hook.vault()), vaultBefore + owed);
        feesSwept += owed;
    }

    function rejectOversizedBuy(uint256 actorSeed) external {
        if (block.timestamp >= hook.openedAt() + 3600) return;
        address actor = actors[actorSeed % actors.length];
        SwapParams memory params = _params(true, false, 10_000_000 ether + 1, false);
        (uint160 priceBefore,,,) = manager.getSlot0(key.toId());
        uint256 feeBefore = hook.accruedFees();
        uint256 claimBefore = manager.balanceOf(actor, uint160(address(pair)));
        uint256 balanceBefore = pair.balanceOf(actor);
        vm.prank(actor);
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.afterSwap.selector,
                abi.encodeWithSelector(SPEPEHook.MaxBuyExceeded.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        router.swap(key, params, 20_000_000 ether, "");
        (uint160 priceAfter,,,) = manager.getSlot0(key.toId());
        assertEq(priceAfter, priceBefore);
        assertEq(hook.accruedFees(), feeBefore);
        assertEq(manager.balanceOf(actor, uint160(address(pair))), claimBefore);
        assertEq(pair.balanceOf(actor), balanceBefore);
        ++rejectedBuys;
    }

    function advance(uint8 blocks_, uint16 seconds_) external {
        vm.roll(block.number + bound(blocks_, 0, 2));
        vm.warp(block.timestamp + bound(seconds_, 0, 600));
    }

    function _params(bool buy, bool exactInput, uint256 amount, bool priceLimited)
        private
        view
        returns (SwapParams memory)
    {
        bool zeroForOne = buy != tokenIs0;
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        if (priceLimited) {
            (uint160 price,,,) = manager.getSlot0(key.toId());
            limit = zeroForOne ? price - price / 20_000 : price + price / 20_000;
        }
        return SwapParams(zeroForOne, exactInput ? -int256(amount) : int256(amount), limit);
    }
}

abstract contract DeferredRefundInvariantBase is LaunchFixture {
    using TransientStateLibrary for IPoolManager;
    DeferredRefundHandler internal handler;
    DeferredRefundRouter internal deferred;
    address[3] internal users;

    function _setupInvariant(bool lowerToken) internal {
        _setup(false, lowerToken, false);
        deferred = new DeferredRefundRouter(manager);
        for (uint256 i; i < users.length; ++i) {
            users[i] = makeAddr(string(abi.encodePacked("claim holder ", bytes1(uint8(65 + i)))));
            token.transfer(users[i], 100_000_000 ether);
            IERC20(IMD).transfer(users[i], 100_000_000 ether);
        }
        handler = new DeferredRefundHandler(hook, deferred, key, users);
        // Every sequence starts with live obligations, including a deferred partial-fill refund.
        handler.trade(0, uint96(500_000 ether), true, true, true);
        handler.trade(1, uint96(500_000 ether), false, false, true);
        assertGt(handler.feesProduced(), 0);
        assertGt(handler.refundsProduced(), 0);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = DeferredRefundHandler.trade.selector;
        selectors[1] = DeferredRefundHandler.redeem.selector;
        selectors[2] = DeferredRefundHandler.transferRefund.selector;
        selectors[3] = DeferredRefundHandler.sweep.selector;
        selectors[4] = DeferredRefundHandler.rejectOversizedBuy.selector;
        selectors[5] = DeferredRefundHandler.advance.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function _assertConservation() internal view {
        uint256 refunds;
        uint256 tokens = token.balanceOf(address(this)) + token.balanceOf(address(manager));
        uint256 paired = IERC20(IMD).balanceOf(address(this)) + IERC20(IMD).balanceOf(address(manager))
            + IERC20(IMD).balanceOf(hook.vault());
        for (uint256 i; i < users.length; ++i) {
            refunds += manager.balanceOf(users[i], uint160(IMD));
            assertEq(manager.balanceOf(users[i], uint160(address(token))), 0);
            tokens += token.balanceOf(users[i]);
            paired += IERC20(IMD).balanceOf(users[i]);
        }
        assertEq(refunds + handler.refundsRedeemed(), handler.refundsProduced());
        assertEq(hook.accruedFees() + handler.feesSwept(), handler.feesProduced());
        assertEq(IERC20(IMD).balanceOf(hook.vault()), handler.feesSwept());
        assertGe(IERC20(IMD).balanceOf(address(manager)), refunds + hook.accruedFees());
        assertEq(tokens, 1e27);
        assertEq(paired, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(manager.getNonzeroDeltaCount(), 0);
        assertEq(manager.balanceOf(address(deferred), uint160(IMD)), 0);
        assertEq(manager.balanceOf(address(hook), uint160(address(token))), 0);
        assertEq(token.balanceOf(address(hook)), 0);
        assertEq(IERC20(IMD).balanceOf(address(hook)), 0);
        assertEq(token.balanceOf(address(deferred)), 0);
        assertEq(IERC20(IMD).balanceOf(address(deferred)), 0);
        assertGt(handler.successfulSwaps(), 1);
    }

    /// @dev After arbitrary sequences, every remaining obligation must still be redeemable.
    function afterInvariant() public {
        handler.sweep(0);
        for (uint256 i; i < users.length; ++i) {
            uint256 claims = manager.balanceOf(users[i], uint160(IMD));
            if (claims != 0) handler.redeem(i, claims);
            assertEq(manager.balanceOf(users[i], uint160(IMD)), 0);
        }
        _assertConservation();
        assertEq(hook.accruedFees(), 0);
    }
}

contract DeferredRefundToken0InvariantTest is DeferredRefundInvariantBase {
    function setUp() public {
        _setupInvariant(true);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_refundsAndFeesRemainBackedAndRedeemable() public view {
        _assertConservation();
    }
}

contract DeferredRefundToken1InvariantTest is DeferredRefundInvariantBase {
    function setUp() public {
        _setupInvariant(false);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_refundsAndFeesRemainBackedAndRedeemable() public view {
        _assertConservation();
    }
}
