// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Test-only router that forwards refund claims instead of redeeming during the swap.
/// All funding, claim transfers and refunds use the entry-point caller; callback data has no payer.
contract DeferredRefundRouter is IUnlockCallback {
    using SafeERC20 for IERC20;

    IPoolManager public immutable manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function swap(PoolKey memory key, SwapParams memory params, uint256 budget, bytes memory hookData)
        external
        returns (BalanceDelta cash, uint256 claims0, uint256 claims1)
    {
        IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(msg.sender, address(this), budget);
        IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(msg.sender, address(this), budget);
        cash = abi.decode(manager.unlock(abi.encode(true, abi.encode(key, params, hookData))), (BalanceDelta));
        claims0 = _forward(key.currency0);
        claims1 = _forward(key.currency1);
        key.currency0.transfer(msg.sender, key.currency0.balanceOfSelf());
        key.currency1.transfer(msg.sender, key.currency1.balanceOfSelf());
    }

    function redeem(Currency currency, uint256 amount) external {
        manager.transferFrom(msg.sender, address(this), currency.toId(), amount);
        manager.unlock(abi.encode(false, abi.encode(currency, amount)));
        currency.transfer(msg.sender, amount);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        (bool isSwap, bytes memory operation) = abi.decode(data, (bool, bytes));
        if (!isSwap) {
            (Currency currency, uint256 amount) = abi.decode(operation, (Currency, uint256));
            manager.burn(address(this), currency.toId(), amount);
            manager.take(currency, address(this), amount);
            return "";
        }
        (PoolKey memory key, SwapParams memory params, bytes memory hookData) =
            abi.decode(operation, (PoolKey, SwapParams, bytes));
        BalanceDelta cash = manager.swap(key, params, hookData);
        _settle(key.currency0, cash.amount0());
        _settle(key.currency1, cash.amount1());
        return abi.encode(cash);
    }

    function _forward(Currency currency) private returns (uint256 amount) {
        amount = manager.balanceOf(address(this), currency.toId());
        if (amount != 0) manager.transfer(msg.sender, currency.toId(), amount);
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
