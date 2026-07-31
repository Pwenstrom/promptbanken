---
target: promptbanken.html
total_score: 19
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 2
timestamp: 2026-07-31T08-03-00Z
slug: promptbanken-html
---
Method: dual-agent (A: design-review · B: detector+browser-evidence)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Copy feedback exists, but selection state can desync silently between card and detail panel with no explanation shown to the user |
| 2 | Match System / Real World | 3 | Swedish plain-language labels and risk terminology (Låg/Medel/Hög) match how caseworkers actually think |
| 3 | User Control and Freedom | 2 | No clear single "back"/deselect path from the workflow panel; clearing quick-input text and clearing filters are two separate, non-adjacent controls |
| 4 | Consistency and Standards | 1 | Duplicate dead info button in every card; three off-palette blues (#1f5fbf, #0052a3, #0066cc) break the One Accent Rule — confirmed independently by the detector (16 color findings) |
| 5 | Error Prevention | 2 | Anonymization reminder present at text entry, but no confirmation gate before Kopiera even when input looks like it still contains PII |
| 6 | Recognition Rather Than Recall | 1 | Two unrelated filter systems both labeled "Roll"/"Målgrupp" sit ~150px apart with different scope (personalize text vs. filter cards) |
| 7 | Flexibility and Efficiency of Use | 2 | Good sidebar/search/sort shortcuts, but the workflow overlay forces a 3-click path (select card → open panel → click Kopiera) instead of a live card-level copy |
| 8 | Aesthetic and Minimalist Design | 2 | Card-level system is genuinely minimal per DESIGN.md; page-level stacks 7+ decision zones (workflow strip, context bar, filter row, advanced filters, stats row, grid toolbar, plus a second Öppen katalog grid) before content repeats |
| 9 | Error Recovery | 1 | Zero-result filter state updates only a text counter; no message or recovery CTA inside the now-empty grid area itself |
| 10 | Help and Documentation | 3 | help.html linked in both sidebar and topbar; inline "Visa exempel" expander is a genuine contextual-help win |
| **Total** | | **19/40** | **Poor — major UX overhaul needed; core browsing experience is functional but internally inconsistent** |

## Design Specificity Verdict

**LLM assessment**: The base layer (Swedish risk-chip taxonomy, per-card anonymization examples, the "Anpassa prompt" export flow) is genuinely authored for this product — a generic SaaS catalog wouldn't ship a risk-level filter or a personnummer/diarienummer checklist wired into the copy path. But the page has been patched by at least two later feature layers (an inline workflow-selection overlay, and a separate Supabase-driven "Öppen katalog" section) that were built without reference to DESIGN.md: they introduce a second and third undocumented blue and a lift-transform on selection that directly contradicts the documented Flat-By-Default and One Accent rules. The content is specific; the newest interaction layer is generic-dashboard drift.

**Deterministic scan**: `detect.mjs --json promptbanken.html` exited 2 with findings across four rules — `design-system-color` (16 occurrences: `#1f5fbf`, `#cfe8d5`, `#eefaf1`, `#166534`, `#f3c7c7`, `#fef2f2`, `#16a34a`, `#dc2626`, `#bfd3f2`, `#ecfdf3`, `#86d19f`, `rgba(31,95,191,0.12)` among them), `design-system-font-size` (5 occurrences: 0.82rem, 1.3rem, 0.94rem, 0.85rem, 1.15rem), `design-system-radius` (1 occurrence: 14px), and `flat-type-hierarchy` (1 aggregate warning: 7 distinct sizes forming only a 1.6:1 scale ratio). All are labeled advisory/quality except the last (warning/slop). No false positives identified — these are literal token-vs-DESIGN.md comparisons, and the tool's own advisory framing already accounts for legitimate semantic colors (success/error greens and reds are plausible intentional additions; the recurring `#1f5fbf` family is not — it directly duplicates the role Civic Blue already fills). The `#1f5fbf` finding independently corroborates Assessment A's "rogue accent color" issue — two independent methods converged on the same defect.

**Visual overlays**: Not available this run. Browser automation tool schemas loaded, but the Chrome extension itself was not connected in this session, so no live tab, no injected detector overlay, and no [Human]-tab visualization could run. Both assessments fell back to static source reading; no live-rendered screenshot was taken, so any purely visual-only defect (e.g. actual contrast rendering, real layout overflow) is not confirmed here.

## Overall Impression

The page's compliance-and-content layer is the real product strength and is worth protecting. But `promptbanken.html` currently reads as three systems stacked in one file — the original static grid, a later workflow-selection overlay, and a Supabase "Öppen katalog" section — none reconciled against DESIGN.md or each other. The single biggest opportunity: reconcile the workflow overlay's colors/motion against the documented system and resolve the duplicate Roll/Målgrupp labeling before adding anything else to this page.

## What's Working

1. **The anonymization example list** (`#anon-examples-modal`) — concrete, domain-specific (personnummer, diarienummer, hälsoinformation) instead of generic PII boilerplate; answers the exact question a caseworker has.
2. **Resting-state card shadow** (`0 1px 2px rgba(16,24,40,0.04)`, style.css:3339) — correctly implements the Flat-By-Default Rule, which is exactly what makes the workflow overlay's departure from it stand out by contrast.
3. **Compliance as a feature, not a disclaimer** — `security_examples` content lives inside the card flow itself, matching the product principle stated in PRODUCT.md rather than being bolted on as a separate legal page.

## Priority Issues

**[P0] Duplicate, dead info button shipped in every card**
- **Why it matters**: `createPromptCard()` emits both a "Förhandsvisa" button and an emoji-labeled "ℹ️ Se hela prompt" button pointing at the same action; only incidental CSS specificity (`.card-actions > .info-btn:not(.secondary-btn) { display: none }`) hides the second one. Any future CSS touch re-exposes two differently-worded buttons doing the same thing, and the dead button may still be screen-reader/keyboard-reachable today.
- **Fix**: Delete the dead button from the template; if a distinct-context variant was intended, gate it with an explicit class, not incidental selector specificity.
- **Suggested command**: `/impeccable harden`

**[P0] Two same-named filter systems with different scope**
- **Why it matters**: `context-filter-controls` (personalizes prompt text) and `advanced-filters` (filters which cards show) both use "Roll" and "Målgrupp" ~150px apart. A user who picks the wrong one gets a result that doesn't match their intent, with no way to tell why — a direct Recognition-not-Recall failure that blocks task completion, confirmed as the lowest-scoring heuristic (1/4).
- **Fix**: Rename one pair (e.g. "Skriv som (roll)" / "Skriv för (målgrupp)" vs. "Filtrera: roll" / "Filtrera: målgrupp") and separate them further visually than the current adjacent-section layout.
- **Suggested command**: `/impeccable clarify`

**[P1] Rogue accent colors breaking the One Accent Rule**
- **Why it matters**: The workflow overlay's inline styles and portions of style.css introduce at least three blues (`#1f5fbf`, `#0052a3`, `#0066cc`) distinct from documented Civic Blue (`#0b63ce`). Confirmed by both the design review and the detector (16 independent color findings) — this is the single most corroborated defect in the report. It quietly erodes the mechanism the whole system depends on: one color meaning "act here."
- **Fix**: Audit every hex blue in style.css and promptbanken.html's inline `<style>` blocks against the DESIGN.md token list; replace non-canonical values with `#0b63ce`/`#084f9e`/`#edf4ff` as appropriate.
- **Suggested command**: `/impeccable polish`

**[P1] No empty-state message when filters/search yield zero cards**
- **Why it matters**: `applyPromptFilters()` only updates a text counter; the grid area itself goes blank with no message and no inline recovery action. Scored as the second-lowest heuristic (Error Recovery, 1/4).
- **Fix**: Render an empty-state block inside `#prompt-grid` ("Inga prompter matchar dina filter — [Rensa filter]") whenever visible count is 0.
- **Suggested command**: `/impeccable onboard`

**[P2] Motion/lift transform on card selection contradicts DESIGN.md**
- **Why it matters**: `.prompt-card.workflow-selected { transform: translateY(-1px); }` is the exact pattern DESIGN.md's Do's and Don'ts forbids ("Don't add motion/lift transforms... the system signals state through color and shadow only").
- **Fix**: Drop the transform; rely on the existing border-color + box-shadow ring already applied in the same rule.
- **Suggested command**: `/impeccable polish`

## Persona Red Flags

**Jordan (First-Timer)**: The workflow-strip declares step 1 as "Välj prompt," but the fully-interactive "Anpassa prompttext" panel (Roll/Målgrupp/Ton) sits visible and interactive before any card is picked, with nothing visually deprioritizing it — Jordan can't tell whether to fill it in first or ignore it. After picking a card, the card's own "Förhandsvisa" button and the detail panel's "Förhandsvisa" button do the same thing with no visible link between them.

**Sam (Accessibility-Dependent)**: `.quick-input-textarea:focus` removes the native outline and substitutes only a border-color change — a materially weaker focus signal than the 2-3px box-shadow ring used elsewhere in the same stylesheet (`.context-filter-control select:focus-visible`), producing inconsistent keyboard-focus visibility on the exact page where DOS-lagen/WCAG 2.1 AA conformance matters most. The dead "ℹ️ Se hela prompt" button may still be in the tab order even though it's visually hidden.

## Minor Observations

- The stats-row risk breakdown ("10 Låg, 5 Medel, 1 Hög") is hardcoded markup, not computed from the live catalog — will silently drift from reality as prompts are added, undermining trust the moment the numbers stop matching.
- The footer's GDPR disclaimer duplicates the detail panel's safety banner — likely intentional given the stakes, but worth confirming it's a deliberate choice rather than an oversight.
- `panel.scrollIntoView({behavior:'smooth'})` fires on every card selection, forcing an unrequested viewport jump that reads as more "consumer app" motion than the system's calm, flat-by-default tone intends.

## Questions to Consider

- If "Anonymisera text" is genuinely step 2 of a declared 3-step workflow, why is the personalization panel fully interactive before step 1 is ever completed?
- The page runs three separately-evolved prompt-browsing systems at once (static grid, Supabase Öppen katalog, workflow-selection overlay) — can a first-time user actually tell these apart?
- DESIGN.md names its rules explicitly so they're checkable — was this page ever checked against them after the workflow overlay shipped?
