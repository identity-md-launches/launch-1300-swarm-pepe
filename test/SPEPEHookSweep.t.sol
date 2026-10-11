// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchFixture} from "./helpers/LaunchFixture.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Test-only fault injection: identical ERC20 storage, but refuses transfers to the vault.
contract VaultRejectingIMD is ERC20 {
    error VaultRefused();
    address internal constant VAULT = 0x3dD5F73dD1A4E62630fAd3909673F130aD429985;

    constructor() ERC20("IMD", "IMD") {}

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == VAULT) revert VaultRefused();
        return super.transfer(to, amount);
    }
}

/// @dev Deposits real backing before minting transferable claims to the hook, in int128 chunks.
/// This reaches accumulated-claim sizes that would otherwise need impractically many swaps.
contract BackedClaimDonor is IUnlockCallback {
    IPoolManager internal immutable manager;
    Currency internal immutable currency;
    address internal immutable beneficiary;

    constructor(IPoolManager pm, Currency c, address recipient) {
        manager = pm;
        currency = c;
        beneficiary = recipient;
    }

    function donate(uint256 amount) external {
        require(IERC20(Currency.unwrap(currency)).transferFrom(msg.sender, address(this), amount));
        manager.unlock(abi.encode(amount));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        uint256 amount = abi.decode(data, (uint256));
        manager.sync(currency);
        currency.transfer(address(manager), amount);
        manager.settle();
        manager.mint(beneficiary, currency.toId(), amount);
        return "";
    }
}

contract SPEPEHookSweepTest is LaunchFixture {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    function setUp() public {
        _setup(false, true, false);
    }

    function test_failedVaultTransferPreservesClaimsAndAllowsRetry() public {
        _trade(true, false, 1_000 ether, false);
        uint256 owed = hook.accruedFees();
        uint256 managerBefore = IERC20(IMD).balanceOf(address(manager));
        uint256 vaultBefore = IERC20(IMD).balanceOf(hook.vault());
        bytes memory workingCode = IMD.code;
        vm.etch(IMD, address(new VaultRejectingIMD()).code);

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                IMD,
                IERC20.transfer.selector,
                abi.encodeWithSelector(VaultRejectingIMD.VaultRefused.selector),
                abi.encodeWithSelector(CurrencyLibrary.ERC20TransferFailed.selector)
            )
        );
        hook.sweep();
        assertEq(hook.accruedFees(), owed, "failed transfer burned the obligation");
        assertEq(IERC20(IMD).balanceOf(address(manager)), managerBefore);
        assertEq(IERC20(IMD).balanceOf(hook.vault()), vaultBefore);
        assertEq(manager.getNonzeroDeltaCount(), 0);

        // Vault transfer failure must not affect swaps, which only accrue ERC-6909 claims.
        _trade(false, true, 1_000 ether, false);
        uint256 total = hook.accruedFees();
        assertGt(total, owed);
        vm.etch(IMD, workingCode);
        assertEq(hook.sweep(), total);
        assertEq(hook.accruedFees(), 0);
        assertEq(IERC20(IMD).balanceOf(hook.vault()), vaultBefore + total);
        assertEq(manager.getNonzeroDeltaCount(), 0);
    }

    function test_sweepDoesNotChangePoolPriceLiquidityOrFeeGrowth() public {
        _trade(true, true, 1_000 ether, false);
        _trade(false, false, 1_000 ether, false);
        (uint160 price, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(key.toId());
        uint128 liquidity = manager.getLiquidity(key.toId());
        (uint256 growth0, uint256 growth1) = manager.getFeeGrowthGlobals(key.toId());
        uint256 tokenReserves = token.balanceOf(address(manager));
        uint256 pairedReserves = IERC20(IMD).balanceOf(address(manager));
        uint256 owed = hook.accruedFees();
        assertGt(owed, 0);
        assertEq(hook.sweep(), owed);
        (uint160 newPrice, int24 newTick, uint24 newProtocolFee, uint24 newLpFee) = manager.getSlot0(key.toId());
        (uint256 newGrowth0, uint256 newGrowth1) = manager.getFeeGrowthGlobals(key.toId());
        assertEq(newPrice, price);
        assertEq(newTick, tick);
        assertEq(newProtocolFee, protocolFee);
        assertEq(newLpFee, lpFee);
        assertEq(manager.getLiquidity(key.toId()), liquidity);
        assertEq(newGrowth0, growth0);
        assertEq(newGrowth1, growth1);
        assertEq(token.balanceOf(address(manager)), tokenReserves);
        assertEq(IERC20(IMD).balanceOf(address(manager)), pairedReserves - owed);
    }

    function test_accumulatedClaimsAcrossInt128BoundaryRedeemInChunks() public {
        _checkAccumulatedClaims(2 * uint256(uint128(type(int128).max)) + 17);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_backedAccumulatedClaimsAlwaysFullySweep(uint256 seed) public {
        uint256 cap = uint256(uint128(type(int128).max));
        _checkAccumulatedClaims(bound(seed, 1, 3 * cap));
    }

    function _checkAccumulatedClaims(uint256 amount) private {
        uint256 cap = uint256(uint128(type(int128).max));
        BackedClaimDonor donor = new BackedClaimDonor(manager, Currency.wrap(IMD), address(hook));
        deal(IMD, address(this), amount, true);
        IERC20(IMD).approve(address(donor), amount);
        uint256 remaining = amount;
        while (remaining != 0) {
            uint256 chunk = remaining > cap ? cap : remaining;
            donor.donate(chunk);
            remaining -= chunk;
        }
        assertEq(hook.accruedFees(), amount);
        uint256 vaultBefore = IERC20(IMD).balanceOf(hook.vault());
        remaining = amount;
        uint256 redeemed;
        while (remaining != 0) {
            uint256 chunk = remaining > cap ? cap : remaining;
            vm.prank(makeAddr("claim sweeper"));
            assertEq(hook.sweep(), chunk);
            remaining -= chunk;
            redeemed += chunk;
            assertEq(hook.accruedFees(), remaining);
            assertEq(IERC20(IMD).balanceOf(hook.vault()), vaultBefore + redeemed);
            assertEq(manager.getNonzeroDeltaCount(), 0);
        }
        assertEq(redeemed, amount);
        assertEq(hook.sweep(), 0);
    }
}

abstract contract FreshManagerBuyCases is LaunchFixture {
    function test_exactOutputBuyOnUnfundedManager() public {
        assertEq(IERC20(IMD).balanceOf(address(manager)), 0);
        _trade(true, false, 1_000 ether, false);
        _sweep();
    }

    function test_exactInputBuyOnUnfundedManager() public {
        assertEq(IERC20(IMD).balanceOf(address(manager)), 0);
        _trade(true, true, 1_000 ether, false);
        _sweep();
    }

    function test_priceLimitedExactInputBuyOnUnfundedManager() public {
        assertEq(IERC20(IMD).balanceOf(address(manager)), 0);
        _trade(true, true, 1_000_000 ether, true);
        assertGt(_refundClaims(), 0);
        _sweep();
    }

    function test_priceLimitedExactOutputBuyOnUnfundedManager() public {
        assertEq(IERC20(IMD).balanceOf(address(manager)), 0);
        _trade(true, false, 1_000_000 ether, true);
        _sweep();
    }

    function _sweep() private {
        uint256 owed = hook.accruedFees();
        uint256 beforeVault = IERC20(IMD).balanceOf(hook.vault());
        assertGt(owed, 0);
        assertEq(hook.sweep(), owed);
        assertEq(IERC20(IMD).balanceOf(hook.vault()), beforeVault + owed);
        assertEq(hook.accruedFees(), 0);
    }
}

contract FreshManagerToken0BuyTest is FreshManagerBuyCases {
    function setUp() public {
        _setup(false, true, true);
    }
}

contract FreshManagerToken1BuyTest is FreshManagerBuyCases {
    function setUp() public {
        _setup(false, false, true);
    }
}
