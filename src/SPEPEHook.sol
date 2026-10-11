// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

/// @notice Immutable SPEPE/IMD launch hook. No administrator and no mutable policy.
contract SPEPEHook is IUnlockCallback {
    error NotPoolManager();
    error InvalidDeployment();
    error InvalidPool();
    error AlreadyInitialized();
    error MaxBuyExceeded();
    error UnrepresentableFee();

    IPoolManager public immutable poolManager;
    address public immutable token;
    address public immutable vault;
    address public constant PAIRED_CURRENCY = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    uint24 public constant LP_FEE = 12_500;
    int24 public constant TICK_SPACING = 60;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant MAX_BUY = TOTAL_SUPPLY / 100;
    uint256 public constant LIMIT_DURATION = 60 minutes;
    uint256 public constant ANTI_SNIPE_BLOCKS = 10;
    uint256 public constant START_FEE_BPS = 3_000;
    uint256 private constant BPS = 10_000;

    bool public initialized;
    uint256 public openedAt;
    uint256 public openedBlock;

    event Opened(uint256 indexed blockNumber, uint256 timestamp);
    event FeeAccrued(address indexed swapper, uint256 filledIMD, uint256 fee, uint256 refundClaims);
    event Swept(address indexed recipient, uint256 amount);

    constructor(IPoolManager manager_, address token_) {
        if (address(manager_) == address(0) || token_ == address(0) || token_ == PAIRED_CURRENCY) {
            revert InvalidDeployment();
        }
        poolManager = manager_;
        token = token_;
        vault = 0x3dD5F73dD1A4E62630fAd3909673F130aD429985;
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory p) {
        p.beforeInitialize = true;
        p.beforeSwap = true;
        p.afterSwap = true;
        p.beforeSwapReturnDelta = true;
        p.afterSwapReturnDelta = true;
    }

    function beforeInitialize(address, PoolKey calldata key, uint160) external onlyPoolManager returns (bytes4) {
        if (initialized) revert AlreadyInitialized();
        (address a, address b) = token < PAIRED_CURRENCY ? (token, PAIRED_CURRENCY) : (PAIRED_CURRENCY, token);
        if (
            Currency.unwrap(key.currency0) != a || Currency.unwrap(key.currency1) != b || key.fee != LP_FEE
                || key.tickSpacing != TICK_SPACING || address(key.hooks) != address(this)
        ) revert InvalidPool();
        initialized = true;
        openedAt = block.timestamp;
        openedBlock = block.number;
        emit Opened(block.number, block.timestamp);
        return IHooks.beforeInitialize.selector;
    }

    function maxBuy() external pure returns (uint256) {
        return MAX_BUY;
    }

    function limitActive() public view returns (bool) {
        return initialized && block.timestamp - openedAt < LIMIT_DURATION;
    }

    /// @notice 3000, 2700, ... 300 bps at offsets 0..9; zero from offset 10.
    function feeBps() public view returns (uint256) {
        if (!initialized) return 0;
        uint256 elapsed = block.number - openedBlock;
        return elapsed < ANTI_SNIPE_BLOCKS ? START_FEE_BPS * (ANTI_SNIPE_BLOCKS - elapsed) / ANTI_SNIPE_BLOCKS : 0;
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        view
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 reserve;
        if (_pairedIsSpecified(key, params)) reserve = _reserve(params.amountSpecified, feeBps());
        // The third return value never overrides the static LP fee.
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(int128(int256(reserve)), 0), 0);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, int128) {
        bool tokenIs0 = Currency.unwrap(key.currency0) == token;
        int128 tokenDelta = tokenIs0 ? delta.amount0() : delta.amount1();
        // Positive token delta is a buy, independent of ordering and exact-input/output mode.
        if (tokenDelta > 0 && limitActive() && uint128(tokenDelta) > MAX_BUY) revert MaxBuyExceeded();

        uint256 rate = feeBps();
        if (rate == 0) return (IHooks.afterSwap.selector, 0);
        int256 pairedDelta = tokenIs0 ? int256(delta.amount1()) : int256(delta.amount0());
        uint256 filled = uint256(pairedDelta < 0 ? -pairedDelta : pairedDelta);
        uint256 fee = filled * rate / BPS;
        uint256 refund;
        bool specified = _pairedIsSpecified(key, params);
        if (specified) {
            // beforeSwap reserved an upper bound; every unused unit belongs to the caller.
            refund = _reserve(params.amountSpecified, rate) - fee;
            if (refund != 0) poolManager.mint(sender, uint160(PAIRED_CURRENCY), refund);
        }
        // Claims do not depend on input tokens already having reached the manager.
        if (fee != 0) poolManager.mint(address(this), uint160(PAIRED_CURRENCY), fee);
        emit FeeAccrued(sender, filled, fee, refund);
        return (IHooks.afterSwap.selector, specified ? int128(0) : int128(int256(fee)));
    }

    function accruedFees() public view returns (uint256) {
        return poolManager.balanceOf(address(this), uint160(PAIRED_CURRENCY));
    }

    /// @notice Anyone can redeem accrued IMD claims to the immutable hackathon vault.
    function sweep() external returns (uint256 amount) {
        if (accruedFees() == 0) return 0;
        return abi.decode(poolManager.unlock(""), (uint256));
    }

    function unlockCallback(bytes calldata) external onlyPoolManager returns (bytes memory) {
        uint256 amount = accruedFees();
        // PoolManager's individual accounting operations use int128, even for accumulated claims.
        if (amount > uint256(uint128(type(int128).max))) amount = uint256(uint128(type(int128).max));
        poolManager.burn(address(this), uint160(PAIRED_CURRENCY), amount);
        poolManager.take(Currency.wrap(PAIRED_CURRENCY), vault, amount);
        emit Swept(vault, amount);
        return abi.encode(amount);
    }

    function _pairedIsSpecified(PoolKey calldata key, SwapParams calldata params) private pure returns (bool) {
        bool specifiedIs0 = (params.amountSpecified < 0) == params.zeroForOne;
        return Currency.unwrap(specifiedIs0 ? key.currency0 : key.currency1) == PAIRED_CURRENCY;
    }

    function _reserve(int256 amount, uint256 rate) private pure returns (uint256 reserve) {
        if (rate == 0 || amount == 0) return 0;
        bool exactInput = amount < 0;
        // Works even for int256.min. FullMath avoids an intermediate multiplication overflow.
        uint256 magnitude = exactInput ? uint256(-(amount + 1)) + 1 : uint256(amount);
        reserve = FullMath.mulDivRoundingUp(magnitude, rate, exactInput ? BPS + rate : BPS - rate);
        // Actual BalanceDelta components cannot exceed 2**127 in magnitude. Cap the reservation
        // at the largest possible fee, allowing very large requests with small partial fills.
        uint256 maximumFillFee = (uint256(1) << 127) * rate / BPS;
        if (reserve > maximumFillFee) reserve = maximumFillFee;
        // PoolManager adds only this capped reservation to amountSpecified. Checking the uncapped
        // quote would reject representable requests that can safely stop at a small partial fill.
        if (!exactInput && reserve > uint256(type(int256).max) - magnitude) revert UnrepresentableFee();
    }
}
