# Swarm Pepe (SPEPE)

The five image-generated logo options are in [`logos/`](logos/README.md). The selected geometric frog wallet mark is [`artifacts/logo.png`](artifacts/logo.png). Each delivered PNG is an opaque 1024×1024 square.

This repository also supplies the required reproducible Foundry launch project: `SPEPE`, `SPEPEHook`, the direct-deployment manifest, and tests using the real Uniswap v4 PoolManager implementation. Dependencies are ordinary vendored source files under `lib/`, with upstream revisions in `lib/versions.json` and their original licenses. No network is required for the default build and test suite.

## Build and test

```sh
forge build
forge test
```

Solidity 0.8.26, Cancun, the optimizer and IR pipeline are pinned in `foundry.toml`; bytecode metadata hashes are disabled. No FFI, filesystem write permissions, external library paths or unlinked libraries are needed.

The fork suite skips explicitly when no RPC URL is configured. Run it against Robinhood Chain:

```sh
ROBINHOOD_RPC_URL=https://rpc.mainnet.chain.robinhood.com forge test --match-contract RobinhoodForkTest -vv
```

By default the fork uses current state because the public RPC prunes older state; `ROBINHOOD_FORK_BLOCK` can pin a block when using an archive RPC. Tests do not broadcast transactions. The fork suite verifies chain ID 4663, IMD's symbol and decimals, then deploys the actual token and a CREATE2-mined hook and trades through the deployed PoolManager. Its funding uses Foundry's test-only balance cheatcode.

## Launch contracts

`SPEPE` is a standard OpenZeppelin ERC-20. It mints exactly 1,000,000,000 tokens with 18 decimals to its deployer, once. There is no public mint, owner, administrator, tax, pause, proxy or upgrade function. The factory handles the 80% pool seed, 10% Merkle distribution and remainder; the token and hook perform none of those allocations.

`SPEPEHook(IPoolManager manager, address token)` is deployed directly. The manifest substitutes `$poolManager` and `$token`; IMD and the hackathon vault are fixed in the implementation. The constructor checks the CREATE2 address permission bits. The low 14 address bits must equal **0x20cc** (8396): `beforeInitialize`, `beforeSwap`, `afterSwap`, `beforeSwapReturnDelta`, and `afterSwapReturnDelta`. All other callbacks are disabled. The tests mine salts and actually deploy the creation code; they do not etch the hook at a chosen address.

Initialization accepts only this token's IMD pair, fee 12500, tick spacing 60 and this hook. It records the opening block and timestamp once. There is no setter and no router/wallet allowlist. Factory deployment and initialization must remain atomic, as specified by the launch.

The pool fee stays at 1.25%. The hook neither uses the dynamic-fee flag nor calls the dynamic fee updater nor overrides the LP fee.

## Hook mechanics

The additional IMD fee is 30% in the initialization block, then 27%, 24%, …, 3% in block offsets 1 through 9, and zero at offset 10. The basis is the absolute IMD amount in the real pool `BalanceDelta`; for IMD input this includes the static pool fee. Final hook fees round down to whole minor units. The hook never swaps, burns or donates the paired token. Burning an ERC-6909 claim during redemption does not burn IMD.

For exact-output buys and exact-input sells, IMD is the unspecified currency: `afterSwap` takes the fee directly from the actual IMD delta using `afterSwapReturnDelta`.

For exact-input buys and exact-output sells, IMD is specified. `beforeSwap` reserves an upper bound using the requested amount `A` and rate `r`:

- Exact input reserves `ceil(A × r / (1 + r))`, leaving the rest of the input budget for the pool.
- Exact output reserves `ceil(A × r / (1 - r))`, increasing the gross pool output to cover the fee.

`afterSwap` calculates the fee from the actual fill and mints the entire excess reservation as IMD ERC-6909 claims to its `sender` (the swapping caller/router). A partial fill, including a zero fill, pays only for what actually filled. The hook ignores `hookData`; callers cannot direct somebody else's refund elsewhere. The included test router burns its refund claims within the same unlock, settles only its net debt, and returns the unspent input budget. Integrating routers must likewise redeem or pass on these claims; they must not strand users' refunds. Rounding can leave a one-unit refund even on a complete fill.

Large requests use full-precision arithmetic and cap the reservation at the largest fee a v4 `int128` fill could generate, allowing small price-limited fills of very large requests. If a positive specified request plus its required fee would overflow `int256`, `UnrepresentableFee` is returned. Normal PoolManager price, liquidity, balance and settlement constraints still apply.

Fees accrue as IMD claims owned by the hook, so swaps do not attempt an IMD transfer before the router has paid. Anyone can call `sweep()` to unlock the manager, redeem those claims and send IMD to **0x3dd5f73dd1a4e62630fad3909673f130ad429985**. No caller can choose a different recipient. A sweep redeems up to the manager's per-operation `int128` bound; additional calls handle larger accumulated balances. The currency is ERC-20 IMD, so ETH reception is irrelevant.

For the first 3,600 seconds, `afterSwap` rejects a **positive launched-token delta above 10,000,000 SPEPE**, using `MaxBuyExceeded`. Exactly the cap is allowed. Sells are unrestricted. At exactly the opening timestamp plus 3,600 seconds, the cap expires. `limitActive()` and `maxBuy()` expose this immutable policy. The rule applies separately to every swap, including multiple swaps from the same router.

## Verification coverage

Local integration tests cover both token orderings, buys and sells in both exact modes, partial fills in all four modes, proportional fees and refund claims, all ten fee-bearing blocks, the fee expiry, both max-buy boundaries, repeated buys, unrestricted sells, arbitrary callers sweeping, callback authentication, single-pool initialization, extreme specified amounts, runtime escape-opcode scans, and EIP-170/EIP-3860 limits. A fresh-manager test seeds only SPEPE before the first IMD-input buy.

Fuzz tests run 1,000 cases per fee/transfer test. Stateful invariants run sequences of swaps, sweeps and time/block advances, independently reconstruct fees from PoolManager swap events, check token conservation and ensure every unlock leaves zero unsettled deltas. The test-only router is under `test/helpers/`; the launch deploys only contracts named in `launch.json`.

The security review focused on manager-only callbacks, immutable policy, exact permissions, specified-side reconciliation, fee conservation, no external token transfers during swaps, no user identity inferred from the router, and fixed-recipient redemption. The hook uses no delegatecall, selfdestruct, proxy, administrator or upgrade mechanism. This is a local implementation review and test report, not an external audit.

## Recorded checks (2026-10-11)

| Check | Result |
| --- | --- |
| `forge build` | Passed with Solidity 0.8.26; compilation performed successfully. |
| Offline tests | 51 passed; the unconfigured fork suite explicitly skips. |
| Supplied protected token and hook tests | All 11 passed, including manifest decimals, policy supply and factory initialization. |
| Robinhood fork, current state via the supplied RPC | All 21 passed, including 1,000 fee fuzz cases. |
| Stateful accounting invariant | 128 sequences, 4,096 calls, zero reverts. |
| Logo files | Five options plus selected artifact: opaque RGB PNG, 1024×1024; visually checked at 64 px and in 32 px circles. |

SPEPE creation/runtime sizes are 2,456/1,503 bytes. SPEPEHook creation/runtime sizes are 5,646/4,867 bytes; its two constructor arguments add 64 bytes to initcode. All are within deployment limits.

An initial historical fork at block 85,796,583 failed because the public RPC had pruned that state; the current-state fork subsequently passed every test. The first invariant run exposed an equal-to-current price limit in the test helper after a direction reversal; offsetting the actual square-root price repaired the helper, and the complete invariant rerun passed. The protected tests were run from unchanged temporary copies with all required probe values supplied; they are not project dependencies.
