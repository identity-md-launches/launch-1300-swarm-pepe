# SPEPE launch accounting review

Scope: `SPEPEHook`, `SPEPE`, the manifest and their Foundry tests. The immutable launch design and the previously repaired reservation overflow boundary are retained. This revision corrects the anti-snipe clock to use Robinhood's local blocks and makes the specified-side router requirement explicit.

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

Refunds belong to the PoolManager's immediate caller, normally a router. The hook ignores hookData and never infers a wallet identity. During the fee window, exact-input buys and exact-output sells require a claim-aware router. It must burn the refund claims within the same unlock **before interpreting output credit or settling cash**, read its updated `currencyDelta`, then settle and pass refunds/proceeds to its user. A router can instead forward claims only if its users explicitly support them and can fund any interim cash debt. The test router demonstrates same-unlock redemption, then settles from its prefunded balance and refunds unused input.

For an exact-output sell with `0 <= q < R`, the raw cash delta `q - R` is negative despite the net proceeds `q - F` being nonnegative. A cash-only router can demand IMD from the seller, strand refund claims, or revert on its positive-output check. The review proof reproduces this: requesting 100,000 IMD at 30%, a tight price limit fills 19,999.000049997500124993 IMD; the cash delta is -22,858.142807145357017865 IMD, the refund is 36,857.442842143607105361 IMD in claims, and their sum is +13,999.300034998250087496 IMD. The vault receives only 5,999.700014999250037497 IMD. Claim redemption restores those positive proceeds without requiring IMD cash from the seller.

The proof's assertion that the raw cash delta must be nonnegative is disputed: the authoritative brief explicitly permits reserving on the specified side and requires refunding excess as ERC-6909 claims to the swapper. Cash-only compatibility for that path is not provided by those semantics. This limitation is now prominent in the manifest and README. No swap mode is blocked and no wallet identity is guessed to redirect claims. Regression tests compare supported and cash-only settlement on identical initial pool states in both token orderings, including a TAKE_ALL-style rejection.

The rounding advisory is reproducible but retained as an intentional policy. `F = floor(abs(q) × r / B)` never charges above the specified rate; rounding up could do so on dust fills. At 30%, an input of 3 minor units reserves 1, fills 2, charges 0 and refunds 1; an input of 10,000 reserves 2,308, fills 7,692, charges 2,307 and refunds 1. The claim-aware router redeems both refunds for its caller. An additional mint for rounding dust is a known gas cost, not additional value taken from the user.

## Representability and the repaired boundary

Each raw BalanceDelta component is `int128`, so `abs(q) <= 2**127`. The reservation can safely be capped at `C = floor(2**127 × r / B)`: it still covers every possible final fee. At the maximum 30% rate, both `C` and `F` fit positive `int128`. The absolute value calculation widens the paired delta to `int256` before negation.

PoolManager adds **the capped reservation** to a positive specified request. The relevant bound is therefore `A <= int256.max - R`, checked after capping. Checking the uncapped quote rejects requests that can safely make small price-limited fills. `FullMath` handles the intermediate multiplication; exact-input magnitude calculation also supports `int256.min`.

The regression test submits `A = int256.max - C` at every fee-bearing block and observes a real partial fill with proportional fees. It then requests one additional unit and expects the wrapped `UnrepresentableFee` error. At offset 10, `C = 0` and an exact-output request of `int256.max` can partially fill with no hook fee. Core price, liquidity, settlement and BalanceDelta representability rules still apply.

## Launch policy and trust boundaries

- The constructor fixes the manager and launch token, fixes the vault from the supplied address, and validates the actual permission bits. It performs no external contract call. Deployment is direct CREATE2, with low 14 address bits `0x20cc`.
- Initialization validates the exact token/IMD pool, static fee and tick spacing, then records the clock once. The factory must deploy and initialize atomically. No arbitrary second pool can restart the fee or limit window.
- Every enabled callback and the sweep unlock callback require the immutable PoolManager. Fee collection calls only its ERC-6909 accounting functions; swaps do not transfer IMD externally or call another pool.
- Fee offsets use `ArbSys(address(100)).arbBlockNumber()`: 3000 bps at local offset 0 through 300 bps at offset 9, then zero. On a plain EVM with no code at ArbSys, the local clock is `block.number`. The constructor does not call ArbSys; the fixed protocol precompile is read at initialization and by `feeBps()`. The 60-minute buy limit uses `block.timestamp` independently. No presumed seconds-per-block conversion is used.
- Max buy checks the actual positive launched-token delta, irrespective of address ordering or exact mode. A rejected swap rolls back price movement, balances and claims. Sells remain unrestricted, and repeated buys are separate swaps.
- `sweep()` burns claims before taking IMD to the fixed vault. PoolManager controls the unlock boundary, and a failed transfer reverts the burn. Larger accumulated claim balances can be redeemed over multiple calls within its `int128` per-operation limit.
- Token supply and distribution remain separate: the token mints all `1e27` units to its deployer. The launch factory performs the specified allocation and sets the opening price. No owner, upgrade, mint-after-construction or mutable fee policy is introduced.

## Evidence

The pre-fix regression failed with `UnrepresentableFee`. The corrected implementation passes it for both token orderings locally and through the deployed Robinhood PoolManager. The suite also reconstructs actual fills from PoolManager events, tests all four swap modes with price limits and empty liquidity, tests an unfunded fresh manager, and checks fee conservation across 128 invariant sequences / 4096 calls. Each fee/request fuzz test runs 1000 cases. Default tests skip an absent fork explicitly; the separate CLI-selected Robinhood fork run executes its assertions without environment-variable reads.

Runtime opcode scans, permission checks, deployment-size checks and the supplied protected token/hook checks supplement those behavior tests. This records local review and execution evidence; it does not claim independent audit or formal verification.

On 2026-10-11, read-only calls against `https://rpc.mainnet.chain.robinhood.com` at block **85,913,395** returned **85,913,395** from `ArbSys.arbBlockNumber()` and **26,169,898** from the initcode `0x4360005260206000f3` (NUMBER; MSTORE; RETURN). `arbChainID()` returned 4663 and ArbSys's code was `0xfe`, the Nitro precompile marker. This matches [Arbitrum's documented distinction](https://docs.arbitrum.io/arbitrum-essentials/arbitrum-vs-ethereum/block-numbers-and-time). Before the correction, the new offline regression recorded 26,000,000 instead of local height 86,000,000, and still returned 3000 bps after ten local blocks with the parent height fixed. Both assertions now pass; all four swap modes remain covered by the existing integration suite.

The fork suite uses Forge 1.8.3's native Nitro support: ArbSys returns the selected local block while NUMBER returns its parent height. It verifies both against RPC calls tagged with the local height, then initializes the hook and trades using native ArbSys plus the real deployed PoolManager and IMD. Only tests that advance the fee window mock ArbSys, so local-block advances leave the parent height fixed. The review's statement that Foundry always seeds NUMBER from the local RPC height does not hold for this version; the original production clock defect still reproduces independently. `test/LaunchClock.t.sol` fuzzes the two clocks separately offline as well.
