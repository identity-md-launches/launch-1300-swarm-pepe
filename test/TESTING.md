# SPEPE contributor test coverage

The added suites extend the existing real-PoolManager tests. No dependency installation is needed; all Solidity imports resolve to files already in this repository.

| Suite | Additional behavior checked |
| --- | --- |
| `SPEPEHookLifecycle.t.sol` | Invalid constructor arguments and address permission bits; rejection of wrong currencies, static/dynamic fee tiers, spacing and hook identity; failed core initialization rolls back the hook clock; initialization cannot restart either window; independent timestamp/block windows; forged callback callers and payloads. |
| `DeferredRefunds.t.sol` | All four swap modes with both currency orderings; deferred ERC-6909 refunds, dust rounding, full and price-limited fills, empty liquidity, claim transfers and later redemption; sweep/refund isolation; forged hook data cannot redirect refunds or waive fees; fee-event accounting. |
| `DeferredRefundInvariant.t.sol` | Three holders swap, transfer claims, redeem, sweep, submit rejected buys and advance time in random order. Each currency ordering runs 256 sequences of depth 64, with unexpected reverts treated as failures. The final drain checks that outstanding obligations remain redeemable. |
| `SPEPEHookSweep.t.sol` | A failed vault transfer preserves claims and can be retried without interrupting swaps; sweeping changes neither pool price, liquidity nor LP fee growth; accumulated claims cross the `int128` boundary and redeem in chunks; buys on a fresh manager with no IMD reserves, in both currency orderings. |

Every new fuzz property uses 1,000 runs through inline Foundry configuration. The existing tests remain in place, including max-buy boundaries, block-by-block fee decay, enormous price-limited requests and their accepted overflow error.

## Independent accounting checks

The new router forwards refund claims to its caller and deliberately leaves redemption for a later transaction. It funds swaps only from its own entry-point caller and authenticates the PoolManager callback. It is test scaffolding, not a launch contract.

Fee expectations are computed from the real PoolManager `Swap` event and the specification's block schedule. Assertions compare the trader's cash plus refund claims with the actual fill minus that fee; SPEPE must remain untaxed. The invariants track produced, outstanding and redeemed refunds separately from produced, outstanding and swept vault fees. They also check fixed supply, token conservation, manager backing and settled transient balances. Each sequence starts with actual swaps and outstanding refunds so the initial accounting checks are non-vacuous.

The large-claim sweep tests deposit backing through a real manager unlock before minting claims to the hook. These deposits exercise aggregate ERC-6909 balances; they are not presented as swap-generated fees. The vault-transfer failure is injected only into the local IMD mock, retaining its ERC20 storage layout. Live IMD behavior is exercised separately on the fork.

## Running the suites

```sh
forge build
forge test
forge test --match-contract '.*RobinhoodForkTest' \
  --fork-url https://rpc.mainnet.chain.robinhood.com --no-storage-caching
```

The last command runs both the existing Robinhood suite and the new deferred-refund suite against the supplied deployed PoolManager and IMD addresses. It checks chain ID, token symbol and decimals. On 2026-10-11, this command passed **31 tests, with no failures or skips**, including three 1,000-case fuzz properties.

An initial attempt to pin RPC block 85,863,111 failed because the public endpoint no longer had that historical state after compilation. The successful run used latest state. With an archive-capable endpoint, add `--fork-block-number` for a reproducible historical snapshot. Hook policy assertions use the hook's EVM opening block and timestamp, not an assumed relation between RPC height and those values.

Without a CLI-selected fork, both fork suites explicitly skip in `setUp`; they do not report unexecuted swaps as passing. A selected wrong chain, missing contract, or failed fork assertion fails the suite. No test calls `vm.setEnv` or reads a private RPC credential. Offline verification needs only the committed tests and existing libraries.

Local validation directs generated outputs to `test/scratch/out` and `test/scratch/cache` with `FOUNDRY_OUT` and `FOUNDRY_CACHE_PATH`. These temporary artifacts are not test dependencies or deliverables.

## Validation results (2026-10-11)

- `forge build`: passed with Solidity 0.8.26 and the existing project configuration.
- Default `forge test`: **96 passed, 0 failed, 2 skipped** (the two offline fork setups).
- Live Robinhood fork command above: **31 passed, 0 failed, 0 skipped**.
- New invariant suites: **32,768 calls**, with zero unexpected reverts. The preserved invariant adds another 4,096 calls.
- No reproducible implementation defect was found in the exercised cases. No implementation changes or additional dependencies were needed.

The small existing-fixture adjustment skips occupied CREATE2 addresses when mining another hook with the same constructor arguments. Lifecycle tests use it to open a distinct pool without replacing deployed hook code.
