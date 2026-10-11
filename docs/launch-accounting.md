# SPEPE launch accounting review

Scope: `SPEPEHook`, `SPEPE`, the manifest and their Foundry tests. The existing immutable launch design is retained. The production correction moves the exact-output overflow check after capping the specified-side reservation.

## Fee and refund equations

Let `B = 10000`, `r` be the current basis-point rate, `A` the absolute specified request, and `q` the signed IMD component of the **pool's actual BalanceDelta**, before hook deltas. The final fee is always `F = floor(abs(q) × r / B)`. The launched-token component is untouched.

| Swap | IMD side | Fee collection |
| --- | --- | --- |
| Exact-input buy | Specified input | Reserve before, reconcile after |
| Exact-output buy | Unspecified input | Return `F` after |
| Exact-input sell | Unspecified output | Return `F` after |
| Exact-output sell | Specified output | Reserve before, reconcile after |

On the unspecified side, the hook returns `F` and mints itself `F` IMD claims. The returned hook credit cancels the mint's debt, and the swapper's IMD delta is `q - F`.

On the specified side, the initial reservation is:

- Exact input: `R = ceil(A × r / (B + r))`.
- Exact output: `R = ceil(A × r / (B - r))`.

The pool can fill at most `A - R` IMD input or `A + R` IMD output, respectively. Both formulas therefore ensure `F <= R`. A partial fill only decreases `F`. The hook mints `F` claims to itself and `R - F` claims to the swapping caller, so its returned credit `R` exactly cancels both mint debts. The caller initially sees `q - R`; redeeming its refund restores `q - F`. A zero fill produces no vault fee and returns the whole reservation.

Refunds belong to the PoolManager's immediate caller, normally a router. The hook ignores hookData and never infers a wallet identity. A production router must redeem or forward the claims for its user. The test router demonstrates redemption within the same unlock, then settles from its prefunded balance and refunds unused input.

## Representability and the repaired boundary

Each raw BalanceDelta component is `int128`, so `abs(q) <= 2**127`. The reservation can safely be capped at `C = floor(2**127 × r / B)`: it still covers every possible final fee. At the maximum 30% rate, both `C` and `F` fit positive `int128`. The absolute value calculation widens the paired delta to `int256` before negation.

PoolManager adds **the capped reservation** to a positive specified request. The relevant bound is therefore `A <= int256.max - R`, checked after capping. Checking the uncapped quote rejects requests that can safely make small price-limited fills. `FullMath` handles the intermediate multiplication; exact-input magnitude calculation also supports `int256.min`.

The regression test submits `A = int256.max - C` at every fee-bearing block and observes a real partial fill with proportional fees. It then requests one additional unit and expects the wrapped `UnrepresentableFee` error. At offset 10, `C = 0` and an exact-output request of `int256.max` can partially fill with no hook fee. Core price, liquidity, settlement and BalanceDelta representability rules still apply.

## Launch policy and trust boundaries

- The constructor fixes the manager and launch token, fixes the vault from the supplied address, and validates the actual permission bits. It performs no external contract call. Deployment is direct CREATE2, with low 14 address bits `0x20cc`.
- Initialization validates the exact token/IMD pool, static fee and tick spacing, then records the clock once. The factory must deploy and initialize atomically. No arbitrary second pool can restart the fee or limit window.
- Every enabled callback and the sweep unlock callback require the immutable PoolManager. Fee collection calls only its ERC-6909 accounting functions; swaps do not transfer IMD externally or call another pool.
- Fee offsets use the EVM's `block.number`: 3000 bps at offset 0 through 300 bps at offset 9, then zero. The 60-minute buy limit uses `block.timestamp` independently. RPC height or a presumed block duration must not be substituted for the contract's exposed clock.
- Max buy checks the actual positive launched-token delta, irrespective of address ordering or exact mode. A rejected swap rolls back price movement, balances and claims. Sells remain unrestricted, and repeated buys are separate swaps.
- `sweep()` burns claims before taking IMD to the fixed vault. PoolManager controls the unlock boundary, and a failed transfer reverts the burn. Larger accumulated claim balances can be redeemed over multiple calls within its `int128` per-operation limit.
- Token supply and distribution remain separate: the token mints all `1e27` units to its deployer. The launch factory performs the specified allocation and sets the opening price. No owner, upgrade, mint-after-construction or mutable fee policy is introduced.

## Evidence

The pre-fix regression failed with `UnrepresentableFee`. The corrected implementation passes it for both token orderings locally and through the deployed Robinhood PoolManager. The suite also reconstructs actual fills from PoolManager events, tests all four swap modes with price limits and empty liquidity, tests an unfunded fresh manager, and checks fee conservation across 128 invariant sequences / 4096 calls. Each fee/request fuzz test runs 1000 cases. Default tests skip an absent fork explicitly; the separate CLI-selected Robinhood fork run executes its assertions without environment-variable reads.

Runtime opcode scans, permission checks, deployment-size checks and the supplied protected token/hook checks supplement those behavior tests. This records local review and execution evidence; it does not claim independent audit or formal verification.
