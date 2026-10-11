# Swarm Pepe (SPEPE)

The five image-generated logo options are in [`logos/`](logos/README.md). The selected geometric frog wallet mark is [`logos/logo-2.png`](logos/logo-2.png). Each original PNG is an opaque 1024×1024 square. The website uses `logos/logo-1.png` as its default, as required by the website brief, and prefers a valid `logo` from the live feed.

This repository also supplies the required reproducible Foundry launch project: `SPEPE`, `SPEPEHook`, the direct-deployment manifest, and tests using the real Uniswap v4 PoolManager implementation. Dependencies are ordinary vendored source files under `lib/`, with upstream revisions in `lib/versions.json` and their original licenses. No network is required for the default build and test suite.

## Website

The complete, dependency-free website is in [`site/`](site/index.html). The publishable static export is in [`dist/`](dist/index.html). Both contain ordinary HTML, CSS and JavaScript; no compilation or dependency installation is needed to serve either folder. The existing contracts, manifest, Foundry configuration and contract dependencies are preserved.

The eight home sections follow the fetched site brief: hero, illustrated story, live stats, interactive buying guide, supply allocation, eight original downloadable memes, a local meme maker, and community/sharing. The Swarm Signal toy sends a little burst of frogs with each ribbit; its percentage is explicitly fictional and local. The sticker supports dragging, arrow-key movement and Home to reset. A sticky-header pause button and device reduced-motion preferences control motion.

### Install, preview and rebuild

Install Node.js 22 or later to use the optional export/preview/check scripts. The site itself has **zero runtime npm dependencies**.

```sh
node scripts/build-site.mjs
node scripts/preview-site.mjs
```

Open `http://127.0.0.1:4173/preview/`. Stop the preview with Ctrl+C. The preview deliberately serves a local **launching** fixture at `/simd-coin.json`, with no token or market figures. It is never copied into the production export. `PORT` can override the preview port.

The production build is a deterministic static export: the script validates page metadata and local HTML asset references, rejects symlinks/dependency folders, and copies `site/` byte-for-byte to `dist/`. This reconciles the brief’s “no build step” source with the required checked-in production export. Edit `site/`, then rerun the export; never hand-edit `dist/`.

### Typecheck and interaction checks

Pinned development tools and their npm lockfile live in `scripts/site-tools/`. Install them outside the repository so no dependency/cache directory can enter the submission:

```sh
mkdir -p /tmp/swarmpepe-site-tools
cp scripts/site-tools/package.json scripts/site-tools/package-lock.json /tmp/swarmpepe-site-tools/
npm ci --prefix /tmp/swarmpepe-site-tools --cache /tmp/swarmpepe-npm --ignore-scripts --no-audit --no-fund
node /tmp/swarmpepe-site-tools/node_modules/typescript/bin/tsc -p scripts/site-tools/tsconfig.json
node --test scripts/test-site.mjs
```

For browser checks on a fresh machine:

```sh
PLAYWRIGHT_BROWSERS_PATH=/tmp/swarmpepe-browsers node /tmp/swarmpepe-site-tools/node_modules/playwright/cli.js install chromium
PLAYWRIGHT_BROWSERS_PATH=/tmp/swarmpepe-browsers node scripts/validate-site.mjs
```

The browser validator starts its own preview on port 4174, runs Chromium, checks interactions and exports, writes evidence, and closes both processes. `SITE_TOOLS` overrides the tool installation directory; `CHROMIUM_PATH` can select an existing Chromium executable. The worker used its supplied Chromium with:

```sh
CHROMIUM_PATH=/opt/imd-worker/local/imd-browser-tool/ms-playwright/chromium-1246/chrome-linux64/chrome node scripts/validate-site.mjs
```

Recorded website results (2026-10-11): production export passed (18 files, 473,012 bytes); JavaScript typecheck passed; 8 unit tests and all 20 browser check groups passed; all 9 tested PNG downloads were valid 1080×1080 images. Home and 404 each had zero detected axe violations at 375px and 1440px; the remaining manual contrast cases and browser limits are in `VALIDATION.md`. The final browser run had no unexpected console errors or failed resources.

The test-only address, market numbers and destinations in the validator are synthetic fixtures. They are absent from both `site/` and `dist/`. Downloaded test PNGs are written to `test/scratch/site/`, outside the submitted export.

### Live data and image downloads

The site requests `/simd-coin.json` on the same origin immediately, every 30 seconds while visible, and when the tab becomes visible. Requests time out after eight seconds; the Refresh control retries. Missing market values are `—`, an absent token is `launching…`, and contract copying stays disabled until a complete nonzero address arrives. Buy and Chart use only their respective feed URLs; before those exist, they lead to the buying guide and stats section. A failed refresh explicitly labels retained values as last-known data.

The launch feed inspected on 2026-10-11 reported `status: building`, no token and no market data. Its actual coin/chart links are read at runtime and are not hardcoded. No official X account was supplied (`x` was null), so the community button opens an X search for the coin; three separate share buttons open prefilled intents. The site makes no wallet connection, submits no personal data, uses no trackers and never sends meme text to a server.

All page artwork and the live meme preview use CSS/SVG with the provided logo. The brief also explicitly requests PNG downloads: a temporary offscreen canvas only rasterizes those downloads to 1080×1080. No canvas renders the interface, and there is no 3D library. Remote selected logos work in the page; exporting them requires the image host to allow CORS. If it does not, PNG export uses the bundled default frog and tells the visitor. Image failure leaves the default mascot usable.

### Publish

Deliver the complete `dist/` directory, including fonts, images, HTML and JavaScript. The IdentityMD publisher serves this export; it does not rebuild it. No deployment or publication command was run. The intended public URL, canonical metadata and share links are `https://swarmpepe.si-md.xyz/`.

Local runtime assets use relative URLs and were checked under `/preview/`, so the export also works at a static-host subpath. The production host supplies the same-origin `/simd-coin.json` endpoint. A plain offline/IPFS mirror without that endpoint shows the honest unavailable/launching state; it still serves the complete site and meme tools. `404.html` is the styled error page; configure the static host to use it for missing pages as appropriate to that host.

Design tokens and reuse rules are in [`DESIGN.md`](DESIGN.md). Actual checks, six-domain design review, screenshots and limitations are recorded in [`VALIDATION.md`](VALIDATION.md). Screenshots and machine-readable reports are emitted under `artifacts/`, which this environment collects separately and excludes from Git. `VALIDATION.md` keeps the review in the repository. The new tooling lockfile is separate from all existing build configuration. No existing package manifest, lockfile, ignore file or dependency was changed.

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
