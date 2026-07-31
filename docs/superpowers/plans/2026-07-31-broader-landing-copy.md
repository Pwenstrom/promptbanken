# Broader Landing Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update `index.html` so Promptbanken's landing page addresses a broader professional audience while keeping public sector as a trust signal.

**Architecture:** This is a static landing-page copy and layout update. Keep the existing hero, CTA, visual example, and trust-strip patterns; add simple content sections below the fold using local CSS classes in `style.css`.

**Tech Stack:** Static HTML, unbundled `style.css`, Vite build.

## Global Constraints

- Do not add backend, Supabase, MCP, or account-tier work.
- Do not claim customer logos, testimonials, measured outcomes, or certifications.
- Do not make Valvet or Pro the main landing-page offer.
- Do not describe AI as automatic decision-making.
- Keep Swedish copy concrete, modern, and professional.
- Preserve the two primary paths: browse prompts on the web or connect through MCP.

---

### Task 1: Landing Copy And Sections

**Files:**
- Modify: `index.html`
- Modify: `style.css`

**Interfaces:**
- Consumes: existing landing layout classes in `index.html` and `style.css`.
- Produces: updated static landing page that builds through Vite.

- [ ] **Step 1: Update metadata and hero copy**

Replace the narrow kommun positioning with:

```html
<title>Promptbanken - svenska promptmallar för arbete med AI</title>
<meta name="description" content="Ett öppet bibliotek med svenska promptmallar för tydligare texter, bättre arbetsflöden och mer ansvarsfull AI-användning.">
```

Hero copy:

```html
<p class="landing-kicker">Öppet bibliotek för arbete med AI</p>
<h1 id="landing-title">Svenska promptmallar för tydligare texter, bättre arbetsflöden och säkrare AI-användning</h1>
<p class="landing-lead">
    Promptbanken hjälper yrkespersoner och organisationer att använda AI mer strukturerat.
    Hitta färdiga mallar för kommunikation, planering, analys och verksamhetsutveckling - anpassade för verkliga arbetsuppgifter.
</p>
```

- [ ] **Step 2: Update trust strip copy**

Use these three trust items:

```html
<p><strong>Öppet att använda.</strong> Sök, öppna och kopiera mallar utan konto.</p>
<p><strong>Byggt för svenska arbetsuppgifter.</strong> Mallar för texter, möten, checklistor, underlag och tydligare kommunikation.</p>
<p><strong>Ansvar från början.</strong> Promptarna påminner om att ta bort personuppgifter och granska AI-svar innan de används.</p>
```

- [ ] **Step 3: Add use-case section**

Add a section after the trust strip:

```html
<section class="landing-section landing-use-cases" aria-labelledby="landing-use-cases-title">
    <div class="landing-section-heading">
        <p class="landing-kicker">Verkliga arbetsuppgifter</p>
        <h2 id="landing-use-cases-title">Kom vidare utan att börja från ett tomt fönster</h2>
        <p>Välj en mall, anpassa den till uppgiften och använd den i det AI-verktyg du redan arbetar med.</p>
    </div>
    <div class="landing-card-grid">
        ...
    </div>
</section>
```

Cards: `Skriv tydligare`, `Strukturera arbete`, `Analysera och jämför`, `Utveckla verksamhet`.

- [ ] **Step 4: Add public-sector and MCP section**

Add a two-column section after use cases:

```html
<section class="landing-section landing-proof-grid" aria-label="Bakgrund och arbetssätt">
    <article class="landing-info-panel">...</article>
    <article class="landing-info-panel">...</article>
</section>
```

Panel 1 heading: `Utvecklad med offentlig sektor som kvalitetskrav`.

Panel 2 heading: `Använd Promptbanken där du redan arbetar`.

- [ ] **Step 5: Add minimal CSS**

Add classes near existing landing CSS:

```css
.landing-section { ... }
.landing-section-heading { ... }
.landing-card-grid { ... }
.landing-info-panel { ... }
.landing-proof-grid { ... }
```

Use existing typography, colors, border radius, and responsive constraints. Do not introduce a new visual theme.

- [ ] **Step 6: Verify and commit**

Run:

```powershell
npm run build
git diff --check
```

Inspect `index.html` for old hero wording:

```powershell
rg -n "Promptbanken för kommun|För kommunala texter" index.html
```

Expected: no matches.

Commit:

```powershell
git add index.html style.css docs/superpowers/plans/2026-07-31-broader-landing-copy.md
git commit -m "feat: broaden landing page positioning"
```
