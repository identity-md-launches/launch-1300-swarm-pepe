# Swarm Pepe website design

## Overview

Swarm Pepe is a meme-coin launch site for people exploring the launch, sharing memes and making their own. The visual identity comes from the supplied `logos/logo-1.png`: electric lime frog, indigo ground and pale eyes. Violet supplies a second loud accent; warm cream supplies contrast. Large Bungee headlines, thick sticker outlines, small tilts, halftone dots and restrained grain give the site its deliberately loud character.

The eight sections in `site/index.html` follow the brief’s order. Content and controls share a centered alignment; decorative stickers can tilt without tilting reading text. The first screen prioritizes the name, plain description, Buy and Chart actions. All production files are exact copies in `dist/`.

## Colors

The canonical tokens are at the start of `site/styles.css`. The implementation is dark only.

| Semantic token | Value | Use |
| --- | --- | --- |
| `--color-bg` | `#101020` | Page, dark button text via `--color-on-action` |
| `--color-surface` | `#17162b` | Cards and alternate section bands |
| `--color-surface-raised` | `#211f38` | Hover fills and secondary controls |
| `--color-text` | `#f3f2df` | Main text, cream buttons and stickers |
| `--color-muted` | `#b8b5cd` | Supporting copy, captions, feed status |
| `--color-action` | `#a8ff00` | Main action, supply allocation, brand emphasis |
| `--color-feature` | `#7c52ff` | Decorative orbit and artwork |
| `--color-secondary` | `#bda5ff` | Section indices, secondary stickers and allocation |
| `--color-border` | `#46425d` | Decorative card/section structure |
| `--color-control-border` | `#79718f` | Visible functional boundaries, fields, outlined actions |
| `--color-focus` | `#f3f2df` | 3px focus ring with dark separation |

Primitive tokens (`--ink-*`, `--lime-400`, `--violet-*`, `--cream-100`) feed semantic roles. Artwork in `site/memes.js` uses a small set of explicit coordinated palettes inside self-contained SVGs. These are illustration colors, not a second UI theme.

Measured sRGB token contrasts include main text/page 16.63:1, muted text/surface 8.88:1, dark text/lime 15.19:1 and functional border/surface 3.85:1. `artifacts/contrast-results.json` records the tested pairs and conservative grain-overlay bounds. Automated scans cannot establish every rotated/image-backed text pair; see the validation limitations.

## Typography

All fonts are bundled WOFF2s with their SIL OFL licenses in `site/assets/fonts/`. No Google Fonts request is made at runtime.

- **Bungee 400**, then Impact / Arial Black / sans-serif: name, section headings, large market figures and supply total. Its chunky letterforms echo the mascot’s rounded outline.
- **Space Grotesk 400, 600 and 700**, then Arial / sans-serif: body, navigation, controls and card titles.
- **Space Mono 400**, then monospace: contract address, ticker, section numbers, coordinate labels and the toy meter.

The six type roles are `--text-small` (0.8125rem), `--text-body` (1rem), `--text-lead` (1.25rem), `--text-card` (1.5rem), `--text-heading` (fluid 2–3.5rem) and `--text-hero` (fluid 4–8rem). The mobile heading role becomes 1.75–2.5rem and hero 3.5–6rem. Intermediate stats scale within the heading role; price uses the card role so small prices remain legible. SVG artwork sizes are independent of this UI hierarchy.

Body line height is 1.6; short display headings use 1.12, with 0.99/1.01 for the two-line name. Display tracking is slightly negative; body text is untracked. Section labels are sentence case, without tracked small capitals. Copy is capped at 66 characters where appropriate. Headings balance, descriptions use pretty wrapping, addresses wrap anywhere, and changing numeric values use tabular figures. Inputs remain at least 1rem. Compact price figures expose their full numeric value through accessible labels.

## Layout

`section-shell` centers content at a maximum 1248px. The initial inline margin is 48px; it becomes 32px below 1100px, 20px below 600px, and 16px below 370px. Spacing tokens use 4, 8, 12, 16, 24, 32, 48, 64 and 96px equivalents. `section-space` uses 96px vertically, then 64px below 850px and 56px below 600px.

The desktop hero, buying guide, allocation and generator use two columns. Stories use three columns; memes use four. At 850px navigation becomes an anchored disclosure, stories become horizontal rows, statistics become two columns and memes become two columns. At 600px the hero, stories, buying guide, allocation and generator stack. The stats grid can fall to one column when enlarged text needs it; meme cards remain two columns with wrapping captions.

The header is sticky. Hash targets account for it through `scroll-padding-top`. The marquee alone has a clipping wrapper for its intentional tilt. The hero artwork has bounded decorative overflow; the page does not hide horizontal overflow globally. Header/actions/badges/allocation rows can wrap, grids can shrink, and headings can break long words under text enlargement.

Browser checks cover 320, 360, 375, 390, 600, 601, 768, 850, 1024, 1440 and 1920px. At 390×844, the name, description and main actions are visible without scrolling. Separate 200% root-font enlargement checks cover 375, 768 and 1440px; this is not a native browser zoom test.

## Elevation & depth

Surfaces are mostly flat, separated by dark tonal bands and structural borders. Main buttons use a 4px hard dark shadow, changing to 6px on hover. Stickers use 3px dark outlines and 5px hard shadows. The mascot has a lime ring with an indigo/violet outer ring; the donut has a hard offset shadow. A low-opacity SVG noise filter overlays the page as CSS background texture, with pointer events disabled.

The sticky header is layer 30, confetti 45, toast 50 and skip link 100. Decorative layers never intercept controls. The menu is an in-flow keyboard disclosure positioned below the sticky header, not a modal.

## Shapes

`--radius-small` is 8px for buttons, fields and compact surfaces; `--radius-card` is 16px for panels/cards; `--radius-pill` is 999px for pills. Mascots use circular crops. Sticker tilts vary intentionally; content panels and prose stay aligned. Avoid applying playful transforms to labels or long reading text.

## Components

| Pattern / source | Behavior and reuse |
| --- | --- |
| `.button`, `.button-outline`, `.button-cream` in CSS | Lime primary, outlined secondary, cream supporting action. Native anchors navigate; native buttons act. 54px default/44px compact targets; focus, hover, active and unavailable states are explicit. |
| `.main-nav`, `.menu-toggle` / `app.js` | Mobile disclosure uses `aria-expanded`, normal Tab order, Escape close and focus return. Link selection closes it. |
| `[data-motion]` / `updateMotion()` | Header icon and footer text control share state. Device reduced-motion preferences take priority. |
| `.stats-grid` / `refreshData()` | Semantic term/value groups, genuine unknown state, manual retry, 30-second visible-tab refresh, eight-second timeout and labelled stale-data state. No simulated market values. |
| `.buy-step`, `.step-panel` / `setStep()` | Three native pressed-state buttons choose steps. Next advances; revealing the coin action moves focus to it. Native details exposes launch rules. |
| `.contract-bar` | Complete feed-supplied address wraps and stays selectable. Copy is disabled until available; clipboard failure exposes the text instead of claiming success. |
| `.vibe-console`, `#drag-sticker` | The explicitly fictional local meter rises by 5 per click, capped at 100%. Frog bursts accompany clicks when motion is allowed. Sticker supports pointer capture, arrow keys and Home. |
| `.donut` | SVG allocation with an accessible label and a complete textual legend. Animates on first scroll reveal only when motion is allowed. |
| `.meme-card`, `memeSvg()` in `memes.js` | Eight original reusable vector compositions incorporating the supplied mascot. Captions and PNG actions have descriptive accessible names. |
| `.generator-controls`, `downloadMeme()` | Four template choices and two labelled local text inputs, each limited to 48 characters. Preview stays SVG. A temporary offscreen canvas encodes 1080px PNG files; busy/error/success states are visible. |
| `.share-link`, `.toast` | Three distinct X intents and a canonical-link copy action. Routine feedback uses a stable polite live region; copy/download errors remain visible. |

Rich motion includes a five-second mascot float, 28-second marquee, six-second sticker wobble, 600ms reveals with 100ms staggering, 900ms donut entrance and brief click bursts. Hover motion is pointer-gated; reduced-motion and pause controls suppress the decorative animations and reveal transforms. The meter label and percentage carry the state without animation.

## Do’s and don’ts

- Reuse `section-shell`, the six typography roles and the three button variants. Reserve the brightest filled action for the local primary task.
- Keep launch information factual. Populate trading URLs, address, logo and metrics from the feed; never fill missing values with a fabricated address, price or official social account.
- Keep new page artwork in CSS/SVG and bundle runtime assets locally. Preserve the original logo files.
- Keep captions, controls and error messages plain even when the surrounding copy is playful. Give every gesture a keyboard path.
- Do not add a wallet connection, tracker, data-collection form, price promise or fictional audit/partner badge.
- To add a page, put its `index.html` in its own folder under `site/`, reference shared assets with the correct relative depth, reuse the header/footer patterns, add page-specific metadata, and rerun the export, typecheck and browser checks. `404.html` demonstrates the shared visual system without home-page JavaScript.

Design knowledge: Jakub Krehel’s Better Interface (MIT), pinned commit `267330e1adfc66a718fb65fa6918c1f06d0a689e`. Documentation method: Paul Bakaus’s Impeccable (Apache-2.0), pinned commit `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8`. Preserved license text and notices are in `docs/design-guidance-LICENSE.txt`.
