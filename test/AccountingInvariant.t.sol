// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LaunchFixture} from "./helpers/LaunchFixture.sol";
import {LaunchRouter} from "./helpers/LaunchRouter.sol";
import {SPEPEHook} from "../src/SPEPEHook.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AccountingHandler is Test {
    using StateLibrary for IPoolManager;
    SPEPEHook public hook;
    IPoolManager public manager;
    LaunchRouter public router;
    PoolKey internal key;
    bool internal tokenIs0;
    uint256 public feesProduced;
    uint256 public successfulSwaps;

    constructor(SPEPEHook h, LaunchRouter r, PoolKey memory k) {
        hook = h;
        manager = h.poolManager();
        router = r;
        key = k;
        tokenIs0 = Currency.unwrap(k.currency0) == h.token();
        IERC20(Currency.unwrap(k.currency0)).approve(address(r), type(uint256).max);
        IERC20(Currency.unwrap(k.currency1)).approve(address(r), type(uint256).max);
    }

    function trade(uint96 seed, bool buy, bool exactInput, bool limited) external {
        uint256 amount = bound(seed, 1 ether, 100_000 ether);
        bool zeroForOne = buy != tokenIs0;
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        if (limited) {
            (uint160 price,,,) = manager.getSlot0(key.toId());
            // A v4 tick can be one below its exact boundary after a downward crossing.
            // Offset the actual price, so reversing direction never requests the current price.
            limit = zeroForOne ? price - price / 20_000 : price + price / 20_000;
        }
        vm.recordLogs();
        router.swap(
            key,
            SwapParams(zeroForOne, exactInput ? -int256(amount) : int256(amount), limit),
            400_000 ether,
            400_000 ether
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 swaps;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(manager)
                    && logs[i].topics[0]
                        == keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
            ) {
                (int128 a, int128 b,,,,) = abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                int256 paired = tokenIs0 ? int256(b) : int256(a);
                uint256 filled = uint256(paired < 0 ? -paired : paired);
                uint256 elapsed = block.number - hook.openedBlock();
                uint256 rate = elapsed < 10 ? 3000 - 300 * elapsed : 0;
                feesProduced += filled * rate / 10_000;
                ++swaps;
            }
        }
        assertEq(swaps, 1, "fee conversion made an extra pool swap");
        ++successfulSwaps;
    }

    function sweep() external {
        hook.sweep();
    }

    function advance(uint8 blocks_, uint16 seconds_) external {
        vm.roll(block.number + bound(blocks_, 0, 2));
        vm.warp(block.timestamp + bound(seconds_, 0, 600));
    }
}

contract AccountingInvariantTest is LaunchFixture {
    using TransientStateLibrary for IPoolManager;
    AccountingHandler internal handler;

    function setUp() public {
        _setup(false, true, false);
        handler = new AccountingHandler(hook, router, key);
        token.transfer(address(handler), 100_000_000 ether);
        IERC20(IMD).transfer(address(handler), 100_000_000 ether);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = AccountingHandler.trade.selector;
        selectors[1] = AccountingHandler.sweep.selector;
        selectors[2] = AccountingHandler.advance.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 32
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_feesConservedAndManagerSettled() public view {
        assertEq(hook.accruedFees() + IERC20(IMD).balanceOf(hook.vault()), handler.feesProduced());
        assertEq(manager.getNonzeroDeltaCount(), 0);
        assertEq(token.balanceOf(address(hook)), 0);
        assertEq(IERC20(IMD).balanceOf(address(hook)), 0);
        assertEq(manager.balanceOf(address(router), uint160(IMD)), 0);
        assertEq(token.totalSupply(), 1e27);
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(address(handler)) + token.balanceOf(address(manager)), 1e27
        );
        assertEq(
            IERC20(IMD).balanceOf(address(this)) + IERC20(IMD).balanceOf(address(handler))
                + IERC20(IMD).balanceOf(address(manager)) + IERC20(IMD).balanceOf(hook.vault()),
            1e27
        );
    }
}
