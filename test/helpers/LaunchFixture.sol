// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SPEPE} from "../../src/SPEPE.sol";
import {SPEPEHook} from "../../src/SPEPEHook.sol";
import {HookFlags} from "../../src/HookFlags.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {LaunchRouter} from "./LaunchRouter.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract LaunchFixture is Test {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    address internal constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address internal constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    uint160 internal constant Q96 = 79228162514264337593543950336;
    uint256 internal constant BUDGET = 100_000_000 ether;
    IPoolManager internal manager;
    SPEPE internal token;
    SPEPEHook internal hook;
    LaunchRouter internal router;
    PoolKey internal key;
    bool internal tokenIs0;

    function _setup(bool fork, bool lowerToken, bool tokenOnly) internal {
        if (fork) {
            manager = IPoolManager(MANAGER);
            assertGt(MANAGER.code.length, 0, "Robinhood PoolManager missing");
            assertGt(IMD.code.length, 0, "Robinhood IMD missing");
            deal(IMD, address(this), 1_000_000_000 ether);
        } else {
            manager = IPoolManager(address(new PoolManager(address(this))));
            deployCodeTo("MockERC20.sol:MockERC20", abi.encode("IMD", "IMD", 1_000_000_000 ether), IMD);
        }
        bytes memory tokenCode = type(SPEPE).creationCode;
        for (uint256 i = 0;; ++i) {
            address predicted = _predict(tokenCode, bytes32(i));
            if ((predicted < IMD) != lowerToken) continue;
            token = new SPEPE{salt: bytes32(i)}();
            break;
        }
        tokenIs0 = address(token) < IMD;
        hook = _deployHook(manager, address(token));
        router = new LaunchRouter(manager);
        key = PoolKey({
            currency0: Currency.wrap(tokenIs0 ? address(token) : IMD),
            currency1: Currency.wrap(tokenIs0 ? IMD : address(token)),
            fee: 12_500,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        token.approve(address(router), type(uint256).max);
        IERC20(IMD).approve(address(router), type(uint256).max);
        manager.initialize(key, Q96);
        if (tokenOnly) {
            router.liquidity(
                key,
                ModifyLiquidityParams(
                    tokenIs0 ? int24(0) : int24(-60), tokenIs0 ? int24(60) : int24(0), 100_000_000 ether, bytes32(0)
                ),
                BUDGET,
                BUDGET
            );
        } else {
            router.liquidity(
                key,
                ModifyLiquidityParams(-887220, 887220, 400_000_000 ether, bytes32(0)),
                400_000_000 ether,
                400_000_000 ether
            );
        }
    }

    function _deployHook(IPoolManager pm, address launchToken) internal returns (SPEPEHook deployed) {
        bytes memory code = abi.encodePacked(type(SPEPEHook).creationCode, abi.encode(pm, launchToken));
        for (uint256 i = 0; i < 200_000; ++i) {
            if (!HookFlags.matches(_predict(code, bytes32(i)), HookFlags.SPEPE_FLAGS)) continue;
            return new SPEPEHook{salt: bytes32(i)}(pm, launchToken);
        }
        revert("no CREATE2 salt found");
    }

    function _predict(bytes memory code, bytes32 salt) internal view returns (address) {
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(code))))));
    }

    function _params(bool buy, bool exactInput, uint256 amount, bool priceLimited)
        internal
        view
        returns (SwapParams memory)
    {
        bool zeroForOne = buy != tokenIs0;
        uint160 priceLimit;
        if (priceLimited) {
            (uint160 price,,,) = manager.getSlot0(key.toId());
            priceLimit = zeroForOne ? price - price / 20_000 : price + price / 20_000;
        } else {
            priceLimit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        }
        return SwapParams(zeroForOne, exactInput ? -int256(amount) : int256(amount), priceLimit);
    }

    function _trade(bool buy, bool exactInput, uint256 amount, bool priceLimited)
        internal
        returns (BalanceDelta net, BalanceDelta raw, uint256 fee)
    {
        uint256 feesBefore = hook.accruedFees();
        uint256 tokenBefore = token.balanceOf(address(this));
        uint256 pairedBefore = IERC20(IMD).balanceOf(address(this));
        vm.recordLogs();
        net = router.swap(key, _params(buy, exactInput, amount, priceLimited), BUDGET, BUDGET);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(manager)
                    && logs[i].topics[0]
                        == keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
            ) {
                (int128 a, int128 b,,,,) = abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                raw = toBalanceDelta(a, b);
                found = true;
            }
        }
        assertTrue(found, "real PoolManager did not swap");
        fee = hook.accruedFees() - feesBefore;
        int256 rawPair = _paired(raw);
        uint256 gross = uint256(rawPair < 0 ? -rawPair : rawPair);
        assertEq(fee, gross * hook.feeBps() / 10_000, "fee is not proportional to actual fill");
        assertEq(_launched(net), _launched(raw), "hook charged SPEPE");
        assertEq(_paired(net), rawPair - int256(fee), "refund/fee accounting mismatch");
        assertEq(int256(token.balanceOf(address(this))) - int256(tokenBefore), _launched(net));
        assertEq(int256(IERC20(IMD).balanceOf(address(this))) - int256(pairedBefore), _paired(net));
        assertEq(manager.getNonzeroDeltaCount(), 0, "manager has unsettled balances");
        assertEq(manager.currencyDelta(address(hook), Currency.wrap(IMD)), 0);
        assertEq(IERC20(IMD).balanceOf(address(hook)), 0, "fee should be a claim");
        assertEq(token.balanceOf(address(hook)), 0);
        (,,, uint24 lpFee) = manager.getSlot0(key.toId());
        assertEq(lpFee, 12_500, "LP fee changed");
    }

    function _paired(BalanceDelta d) internal view returns (int256) {
        return tokenIs0 ? int256(d.amount1()) : int256(d.amount0());
    }

    function _launched(BalanceDelta d) internal view returns (int256) {
        return tokenIs0 ? int256(d.amount0()) : int256(d.amount1());
    }

    function _refundClaims() internal view returns (uint256) {
        return tokenIs0 ? router.lastRefund1() : router.lastRefund0();
    }
}
