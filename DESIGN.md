---
name: Promptbanken
description: A calm, trustworthy civic workbench for finding and adapting safe AI prompts
colors:
  civic-blue: "#0b63ce"
  civic-blue-hover: "#084f9e"
  civic-blue-deep: "#0b3a82"
  civic-blue-tint: "#edf4ff"
  civic-blue-border: "#bfd7ff"
  neutral-ink: "#101828"
  neutral-body: "#344054"
  neutral-muted: "#667085"
  neutral-border: "#dfe6ee"
  neutral-surface: "#f8fafc"
  neutral-white: "#ffffff"
  error: "#b42318"
  success: "#067647"
  warm-accent: "#b7791f"
typography:
  display:
    fontFamily: "'Source Serif 4', Georgia, serif"
    fontSize: "clamp(2.9rem, 5.4vw, 4.7rem)"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.01em"
  kicker:
    fontFamily: "ui-monospace, SFMono-Regular, Consolas, monospace"
    fontSize: "0.9rem"
    fontWeight: 850
    letterSpacing: "0.03em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.55
rounded:
  sm: "4px"
  md: "8px"
  lg: "10px"
  xl: "12px"
  pill: "20px"
  circle: "50%"
spacing:
  sm: "0.55rem"
  md: "1rem"
  lg: "1.8rem"
components:
  button-primary:
    backgroundColor: "{colors.civic-blue}"
    textColor: "{colors.neutral-white}"
    rounded: "{rounded.sm}"
    padding: "0.8rem 1.05rem"
  button-primary-hover:
    backgroundColor: "{colors.civic-blue-hover}"
  button-secondary:
    backgroundColor: "{colors.neutral-white}"
    textColor: "{colors.civic-blue}"
    rounded: "{rounded.sm}"
    padding: "0.8rem 1.05rem"
  card-prompt:
    backgroundColor: "{colors.neutral-white}"
    rounded: "{rounded.md}"
    padding: "1rem"
---

# Design System: Promptbanken

## Overview

**Creative North Star: "The Civic AI Workbench"**

Promptbanken presents itself as a calm, trustworthy workspace — not a
consumer app and not a flashy AI product. The system reads as institutional
without being cold: a serif display face gives headlines quiet authority,
while a plain system-font body keeps working content scannable. Civic Blue
is used sparingly and consistently as the single signal of interactivity
and trust; everything else stays near-neutral ink and gray. Cards and
controls sit flush against the page at rest — depth appears only as a
response to hover or selection, never as ambient decoration. The whole
system optimizes for people who need to trust a tool quickly and then get
back to their actual work.

**Key Characteristics:**
- One accent color (Civic Blue), used narrowly and repeated exactly
- Serif display type for headline authority, system sans for everything read at speed
- Flat-by-default surfaces; shadow is a state signal, not a resting decoration
- Small, consistent radii (4–8px) — precise, not playful
- Monospace used only for kickers/labels/technical strings, never body copy

## Colors

Palette is restrained: one primary accent, a tight neutral-gray scale for text and structure, and small semantic accents for state.

### Primary
- **Civic Blue** (`#0b63ce`): primary action color — buttons, links, selection state, icon marks. Used narrowly; its rarity is what makes it read as a signal rather than decoration.
- **Civic Blue Deep** (`#0b3a82`): brand wordmark / highest-emphasis text-on-light use of the accent.
- **Civic Blue Tint** (`#edf4ff`): the accent's background form — icon chips, hover backgrounds, active nav state.

### Neutral
- **Ink** (`#101828`): primary heading and high-emphasis text.
- **Body** (`#344054`): running body text, nav labels.
- **Muted** (`#667085`): secondary/supporting text, lead paragraphs, captions.
- **Border** (`#dfe6ee`): default card and input borders.
- **Surface** (`#f8fafc`): subtle section backgrounds.
- **White** (`#ffffff`): card and control backgrounds.

### Semantic accents
- **Error** (`#b42318`): validation errors, destructive states, risk warnings.
- **Success** (`#067647`): confirmations, positive status.
- **Warm Accent** (`#b7791f`): favorites/warm-highlight states, used only where the blue system explicitly steps aside.

### Named Rules

**The One Accent Rule.** Civic Blue is the only color that means "act here." It never competes with a second bright accent on the same screen; warm accent and semantic colors are reserved for their own distinct meanings (favorite, error, success), never substituted for the primary action color.

## Typography

**Display Font:** "Source Serif 4" (with Georgia, serif fallback)
**Body Font:** -apple-system / Segoe UI / Roboto / Helvetica Neue / Arial, sans-serif
**Label/Mono Font:** ui-monospace, SFMono-Regular, Consolas, monospace

**Character:** A serif/sans pairing that separates "this is a considered statement" (serif headlines) from "this is a tool you operate" (sans everything else) — the same distinction the product itself makes between persuasive framing and working UI.

### Hierarchy
- **Display** (700, `clamp(2.9rem, 5.4vw, 4.7rem)`, line-height 1.05): hero/landing headlines only, serif, tight letter-spacing (-0.01em).
- **Kicker/Label** (850, 0.9rem, uppercase, letter-spacing 0.03em, monospace): eyebrow labels above headlines, technical field labels.
- **Title** (600–800, ~1–1.1rem): card titles, section headings, sans-serif.
- **Body** (400, ~0.88–1.16rem, line-height 1.5–1.55): running text and descriptions; lead paragraphs cap around 58ch.
- **Label/small** (400–700, ~0.75–0.9rem): captions, chips, secondary metadata.

### Named Rules

**The Serif-Is-Rare Rule.** The serif display face appears only on true headline moments (landing hero, top-level page titles). Every operational surface — cards, forms, nav, admin — stays in the sans body font. Serif never leaks into UI chrome.

## Layout

Landing/marketing surfaces use a wide two-column hero grid (`minmax(360px, 0.9fr) minmax(380px, 1fr)`) with generous clamp()-based padding that scales from mobile to desktop. Operational surfaces (catalog, admin) use card grids with consistent gutters. Content max-widths are set per element for readability: hero copy at 720px, lead paragraphs at 58ch. Responsive behavior collapses the hero grid and reduces topbar/heading sizes at narrower breakpoints rather than changing the visual language.

## Elevation & Depth

Flat-by-default. Surfaces sit at rest with a near-invisible shadow (`0 1px 2px rgba(16,24,40,0.04)`) or none at all — depth is not used to convey importance at rest. Shadow strengthens only as a direct response to interaction: hover lifts a card to `0 8px 24px rgba(16,24,40,0.08)`, and selection adds a focused ring-style shadow (`0 0 0 2px rgba(11,99,206,0.15)`) rather than more elevation. Larger ambient shadows (`0 28px 70px rgba(16,24,40,0.12)`) appear only on hero showcase elements (e.g. the klarspråk before/after card), never on ordinary UI.

### Shadow Vocabulary
- **Resting** (`box-shadow: 0 1px 2px rgba(16,24,40,0.04)`): default card/control state.
- **Hover** (`box-shadow: 0 8px 24px rgba(16,24,40,0.08)`): interactive lift on pointer hover.
- **Selected/focus ring** (`box-shadow: 0 0 0 2px rgba(11,99,206,0.15)`): selection or focus state, colored with Civic Blue at low opacity.
- **Showcase** (`box-shadow: 0 28px 70px rgba(16,24,40,0.12)`): reserved for hero-level signature elements only.

### Named Rules

**The Flat-By-Default Rule.** Surfaces are flat at rest. Shadow only appears as a response to state (hover, selection, focus) or on the single hero showcase element per page — never as ambient decoration on ordinary cards or panels.

## Shapes

Small, consistent radii signal precision rather than friendliness: 4px for compact controls and chips, 8px for cards and standard buttons, 10–12px for larger containers and showcase cards, 20px for pill-shaped elements, and 50% for circular badges (e.g. the selection checkmark). Borders are thin (1px) and low-contrast (`#dfe6ee` family) at rest, strengthening only on hover/selection.

## Components

The buttons/cards/inputs feel: **restrained and precise** — small radii, thin borders, subtle shadow, no flashy motion. Built for scanning and trust, not for delight.

### Buttons
- **Shape:** 7–8px radius, never fully rounded.
- **Primary:** Civic Blue background (`#0b63ce`), white text, ~0.8rem 1.05rem padding, 850 font-weight.
- **Primary hover:** darkens to `#084f9e`; no transform/lift.
- **Secondary:** white background, Civic Blue text, 1px `#bfd7ff` border; hover fills to `#f4f8ff`.

### Cards / Containers (prompt-card)
- **Corner Style:** 8px radius.
- **Background:** white on `#dfe6ee` border.
- **Shadow Strategy:** resting → hover → selected, per Elevation section above.
- **Selected state:** border becomes Civic Blue, shadow becomes the focus ring.
- **Internal Padding:** 1rem, with a small icon chip (38px, 8px radius, Civic Blue Tint background) leading the title row.

### Navigation (landing-topbar / landing-nav)
- **Style:** translucent white topbar (`rgba(255,255,255,0.94)` + backdrop-filter blur), thin bottom border, 76px min-height.
- **Nav links:** 7px radius, muted body-gray text at rest; hover fills Civic Blue Tint background with Civic Blue text — no underline.

## Do's and Don'ts

### Do:
- **Do** keep Civic Blue as the only color that signals an action — buttons, active nav, selection, links.
- **Do** keep shadows flat at rest and reserve elevation for hover/selection/focus state changes.
- **Do** use the serif display face only for true headline moments; keep every operational surface in the sans body font.
- **Do** use small radii (4–8px) consistently; reserve 10px+ and pill/circle shapes for the specific container types already using them (showcase cards, pills, circular badges).

### Don't:
- **Don't** introduce a second bright accent color competing with Civic Blue for attention.
- **Don't** add ambient/resting shadows to ordinary cards or panels — depth is earned by interaction, not decoration.
- **Don't** use the serif face in UI chrome, forms, or admin surfaces — it is reserved for landing/marketing headlines.
- **Don't** add motion/lift transforms to buttons or cards; the system signals state through color and shadow only, not transform.
