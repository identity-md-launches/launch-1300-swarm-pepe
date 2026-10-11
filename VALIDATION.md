# Swarm Pepe website validation

Date: 2026-10-11. Scope: the new static website and its export; the accepted Solidity contracts, deployment manifest, Foundry configuration and vendored contract dependencies were preserved.

## Brief, implementation and assumptions

The full JSON `brief` was retrieved from `https://www.si-md.xyz/api/chat?op=site-brief&label=swarmpepe` before implementation. The pinned Better Interface workflow and all six core domains were read and used during construction. The complete brief’s eight sections and their order are implemented, including both meme features.

- Source is plain HTML/CSS/JS in `site/`, with home and `404.html`. `dist/` is the required production export. The build is validation plus a byte-for-byte copy, not a compiler or bundler; the source itself is directly servable.
- `logos/logo-1.png` supplies the default mascot, favicon and social image. Optimized runtime derivatives preserve the original image. Every original logo remains untouched. A valid feed `logo` replaces displayed mascots and meme previews.
- CSS and SVG render the page. The contradictory “no canvas” / “canvas PNG generator” requirements are resolved narrowly: canvas exists only offscreen while encoding a PNG download. There is no canvas interface, rendering framework or 3D dependency.
- The live endpoint was inspected: it reported `building`, a null token, null market, null logo and null X account. No deployment address or live figures are invented. The X community link therefore uses a search for the actual coin name/ticker; no official handle is fabricated.
- No wallet connection, tracking, data collection, transaction signing or publishing was performed. Local meme text is not submitted anywhere. External links open only when the visitor activates them.
- The test-only feed in `scripts/preview-site.mjs` and synthetic browser fixtures are never exported. Real Buy/Chart URLs come only from `/simd-coin.json`.

## Actual commands and results

| Check | Actual result |
| --- | --- |
| `node scripts/build-site.mjs` | Passed. 18 production files, 473,012 bytes; every file copied from `site/`. |
| `node /tmp/swarmpepe-site-tools/node_modules/typescript/bin/tsc -p scripts/site-tools/tsconfig.json` | Passed with no diagnostics. TypeScript 5.9.3 checks all three JavaScript modules with `checkJs`, `allowJs`, `noEmit`. |
| `node --test scripts/test-site.mjs` | 8 tests passed: safe URLs, market validation, complete/nonzero addresses, prelaunch null state, malformed feeds, number formatting, SVG escaping, page metadata. |
| `CHROMIUM_PATH=/opt/imd-worker/local/imd-browser-tool/ms-playwright/chromium-1246/chrome-linux64/chrome node scripts/validate-site.mjs` | Exit 0. All 20 browser check groups passed. Playwright 1.58.2 with the worker’s installed Chromium. |
| PNG downloads | All 8 gallery outputs and 1 custom text/template output downloaded successfully. PNG signatures and 1080×1080 dimensions checked; all outputs contained substantial image data. A gallery PNG was also visually inspected. |
| Axe 4.11.0 | Zero detected A/AA violations on home and 404, each at 375px and 1440px. Home has manual-review contrast cases; see limitations below. |
| Browser console/network | Zero unexpected console errors and zero failed resources in the final run. An intentionally injected HTTP 503 verifies the stale-data state and is excluded from the unexpected-error count. |
| `forge build` | Passed using Solidity 0.8.26. Existing contract lint warnings (casts, timestamp, local initialization and event ordering) remain; Solidity was not modified by this website task. |
| `forge test` | 51 passed, 0 failed, 1 explicitly skipped fork setup. Includes 1,000-case fuzz tests and 128 invariant sequences / 4,096 calls with zero reverts. |

The final browser report is `artifacts/browser-results.json`. It records the 20 check groups, viewport measurements, nine PNG sizes, four accessibility scans and empty unexpected-error/resource-failure arrays. Temporary downloaded images are under `test/scratch/site/` and are not submission dependencies.

## Interaction and layout coverage

The final export was served at `/preview/` to check relative asset resolution. Tests covered:

- Prelaunch, deployed-address and live-market states; address copy; supplied Buy/Chart links; a selected-logo override; stale data after HTTP failure and successful recovery. Buy was clicked through to a routed test destination in a new tab.
- Automatic polling after 30 seconds using an isolated browser virtual clock, without a real-time 30-second wait. Manual refresh and visible-tab behavior remain in the implementation.
- Mobile navigation, hash anchors, Escape/focus return, first keyboard skip link, the visible 3px primary focus ring, buying-guide step selection/advancement, the newly revealed coin action’s focus, and expanded launch rules.
- Pointer and keyboard sticker movement, Home reset, the local ribbit meter, share intent contents and clipboard, template/text edits, all gallery downloads and the custom PNG download.
- Device reduced-motion emulation: float and marquee disabled, no frog bursts, controls still functional. An always-available sticky-header control and footer control also toggle motion.
- Document-width checks at 320, 360, 375, 390, 600, 601, 768, 850, 1024, 1440 and 1920px. At 390×844, the product, explanation and primary action are above the fold. Live small-price/long-address checks also pass at 320, 390, 768 and 1440px.
- 200% root-font enlargement at 375, 768 and 1440px, with no horizontal overflow. This is a text-enlargement test, not a browser-native zoom session.
- Both 404 widths, working home links, all internal anchor targets, no broken HTML images, local font loading and static resources.

Visual evidence: `artifacts/desktop.jpg` (1440px full page) and `artifacts/mobile.jpg` (390×844 first screen). Both were opened and visually inspected. Earlier browser-tool screenshots also covered the desktop hero and meme wall; a focused-primary-action screenshot was inspected from the temporary test output. All five intended WOFF2 faces were observed loaded in the browser.

## Better Interface review: six domains

| Domain | Coverage and evidence | Status / boundaries |
| --- | --- | --- |
| Accessibility | Native elements, heading/landmark outline, alt purposes, input labels, descriptive downloads, live statuses, target sizes, skip/focus, menu Escape, gesture alternatives, reduced motion, four axe scans. | Checked. No physical screen-reader session; see contrast/manual limitations. |
| Layout | Eight-section order, clear first-screen action, shared alignment, 11 viewport widths, long live data, enlarged text, menu and card reflow. Hero, full page and mobile screenshots inspected. | Checked. Browser-native zoom and physical devices unperformed. |
| Writing | Coin-specific copy, plain buying steps, fee/cap disclosure consistent with accepted contracts, honest prelaunch/stale states, action labels, visible fictional-meter disclaimer, no return promises or invented accounts/audits. | Checked in source and browser. English only is intentional. |
| Typography | Six semantic type roles, supplied WOFF2 weights, loaded fonts, descending heading roles, body line-height/measure, numeric stability, full address wrap, no small tracked heading eyebrows. | Checked. SVG illustration lettering is separate from UI type. |
| Colors | Role tokens, corrected functional boundary contrast, computed WCAG sRGB pairs with conservative grain bound, visible dark/lime/cream states. | Checked for listed pairs. Automated home scans leave 54/55 contrast nodes for manual review; not every artwork pixel is certified. |
| UI | Hover/focus/pressed/unavailable states, rich but pausable motion, loading/retry/stale states, selected guide controls, download busy/success/error feedback, consistent card/button treatment. | Checked. Animation-panel 10% playback and every external-logo host variant unperformed. |

Light theme, RTL/localization, modal focus traps, account flows and destructive-action confirmation are not applicable to this brief. No extra features were added merely to fill review categories.

## Findings, fixes and rechecks

| Severity | Source location | Concrete finding and correction | Recheck |
| --- | --- | --- | --- |
| Medium | `site/index.html:68`; `site/styles.css:18` | At 601px the tilted marquee made document width 602px. Added a clipping wrapper around that deliberately tilted decoration. | All 11 final width checks pass. |
| High | `site/index.html:81` | Axe reported an invalid definition list because metric captions were `div > span` children inside `dl`. Captions now use additional `dd` elements with a distinct caption class. | Home axe scans report zero violations. |
| Medium | `site/index.html:51`; `site/index.html:87` | Axe required manual review of `aria-label` on generic divs. Named hero-art and buying-step containers now have the valid `group` role. | `aria-prohibited-attr` no longer appears in incomplete results. |
| Medium | `site/styles.css:31` | The initial decorative border `#46425d` on surface `#17162b` measured only 1.85:1 when used as a functional input/control boundary. Added dedicated `--color-control-border: #79718f`. | The corrected pair measures 3.85:1; conservative grain bound 3.74:1. Decorative borders retain their quieter role. |
| Medium | `site/styles.css:35`; `site/styles.css:41` | 200% text enlargement initially produced a 483px document at 375px and decorative art overflow at 768px. Enabled wrapping, shrinkable columns and content-sized stats; contained hero artwork. | Final enlarged-text checks pass at 375, 768 and 1440px without hiding overflow on the whole page. |
| Medium | `site/index.html:38`; `site/app.js:39` | The first implementation exposed pause only in the footer while autoplay is visible in the hero. Added a sticky-header pause control sharing state and respecting the OS preference. | Header control appears in final screenshots; reduced-motion tests pass. |

Additional preventive improvements: compact small-price notation with a full accessible numeric value (`site/data.js:35`, `site/app.js:76`), persistent copy/download error text, and CORS-safe default-logo fallback for PNG export. The final browser suite verifies small prices and complete addresses at four widths.

Verification infrastructure corrections were separate from product findings. The initial ad hoc preview process expired, so the repeatable validator now owns both server and browser in one command. The first timer assertion raced a tab-visibility refresh; the polling check now uses an isolated virtual-clock page. The final 404 return-loop test waits for page/font loading so its own next navigation does not cancel in-flight fonts. All final checks pass.

## Contrast measurements

The calculations use the WCAG sRGB relative-luminance formula on actual CSS token values. Primary pairs: cream/page 16.63:1; cream/surface 15.66:1; muted/surface 8.88:1; lavender/surface 8.42:1; dark/lime 15.19:1; control boundary/surface 3.85:1. Muted text against the brighter community dot color is 6.05:1. `artifacts/contrast-results.json` lists every pair and a conservative maximum-white grain-overlay bound; the lowest checked text bound is 5.83:1 and the control boundary bound is 3.74:1.

These are calculated token-pair measurements, not invented pixel-sampled ratios. The corresponding backgrounds and states were inspected in screenshots. The low-opacity noise, rotated stickers, symbols and SVG art leave automated contrast cases unresolved; no claim of comprehensive pixel-by-pixel contrast or full accessibility certification is made.

## Remaining limits

- No real token address, price or market cap existed in the inspected feed. Deployed states and quote-link behavior were tested with clearly separated fixtures; no live purchase was made.
- The accepted Robinhood fork suite was not rerun against live state for this website-only change. The default `forge test` explicitly skipped it because no fork URL was set. Prior contributor fork results in README are historical, not newly claimed here.
- Chromium was used; Firefox, WebKit, physical iOS/Android, a real screen reader and native 200% browser zoom were not exercised. Text enlargement/reflow and keyboard tests are narrower evidence.
- Axe reports zero violations but 54/55 home contrast nodes are incomplete, largely symbols, textures, rotated labels and SVG illustration text. The listed CSS text/control pairs were measured separately; the entire artwork is not contrast-certified.
- External X authentication, feed publication after deployment, remote-logo CORS policies and the public host’s custom-404 routing are outside local verification. The direct exported `404.html` works at both required widths.
- Cross-origin selected-logo export falls back to the bundled image when CORS prevents reading it; the visitor is told. Clipboard denial exposes selectable text instead of reporting false success.
- No Lighthouse score, real-user performance claim, animation-panel slow-motion review or all-screen-reader compliance claim is made. The interface reserves image dimensions and bundles its fonts locally.

## Delivery and size

`site/` and `dist/` contain the same 18 files, including all runtime assets and font licenses. The tooling manifest/lockfile is under `scripts/site-tools/`; installed packages and caches stayed in `/tmp`. No dependency archive, registry mirror, submodule, `node_modules`, cache, generated contract output or input reference is part of the website export. Existing ignore rules and protected files were not modified.

The environment excludes `artifacts/` from Git and collects those files separately. `VALIDATION.md` is the repository copy of this report; screenshots and raw reports remain named artifacts. Design-guide attribution/license text is also preserved in `docs/design-guidance-LICENSE.txt`, independent of artifact handling. The final size check is recorded in `artifacts/submission-size.json` and includes the artifact files conservatively.
