// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Integration-test router. Each entry pre-funds from its own caller, burns refund claims,
/// settles from its own balance, and refunds the unspent budget. Not a launch deployment.
contract LaunchRouter is IUnlockCallback {
    using SafeERC20 for IERC20;
    using TransientStateLibrary for IPoolManager;

    IPoolManager public immutable manager;
    uint256 public lastRefund0;
    uint256 public lastRefund1;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function swap(PoolKey memory key, SwapParams memory params, uint256 budget0, uint256 budget1)
        external
        returns (BalanceDelta delta)
    {
        _fund(key, budget0, budget1);
        delta = abi.decode(manager.unlock(abi.encode(true, key, abi.encode(params))), (BalanceDelta));
        _refund(key);
    }

    function liquidity(PoolKey memory key, ModifyLiquidityParams memory params, uint256 budget0, uint256 budget1)
        external
        returns (BalanceDelta delta)
    {
        _fund(key, budget0, budget1);
        delta = abi.decode(manager.unlock(abi.encode(false, key, abi.encode(params))), (BalanceDelta));
        _refund(key);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (bool isSwap, PoolKey memory key, bytes memory operation) = abi.decode(data, (bool, PoolKey, bytes));
        if (isSwap) manager.swap(key, abi.decode(operation, (SwapParams)), "");
        else manager.modifyLiquidity(key, abi.decode(operation, (ModifyLiquidityParams)), "");

        lastRefund0 = _burnRefund(key.currency0);
        lastRefund1 = _burnRefund(key.currency1);
        int256 d0 = manager.currencyDelta(address(this), key.currency0);
        int256 d1 = manager.currencyDelta(address(this), key.currency1);
        _settle(key.currency0, d0);
        _settle(key.currency1, d1);
        return abi.encode(toBalanceDelta(int128(d0), int128(d1)));
    }

    function _burnRefund(Currency currency) private returns (uint256 amount) {
        uint256 id = uint160(Currency.unwrap(currency));
        amount = manager.balanceOf(address(this), id);
        if (amount != 0) manager.burn(address(this), id, amount);
    }

    function _fund(PoolKey memory key, uint256 a, uint256 b) private {
        if (a != 0) IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(msg.sender, address(this), a);
        if (b != 0) IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(msg.sender, address(this), b);
    }

    function _refund(PoolKey memory key) private {
        key.currency0.transfer(msg.sender, key.currency0.balanceOfSelf());
        key.currency1.transfer(msg.sender, key.currency1.balanceOfSelf());
    }

    function _settle(Currency currency, int256 delta) private {
        if (delta < 0) {
            manager.sync(currency);
            currency.transfer(address(manager), uint256(-delta));
            manager.settle();
        } else if (delta > 0) {
            manager.take(currency, address(this), uint256(delta));
        }
    }
}
