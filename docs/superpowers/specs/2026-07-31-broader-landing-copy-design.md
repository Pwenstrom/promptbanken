# Broader Landing Copy Design

Date: 2026-07-31

## Purpose

Promptbanken has moved from being framed primarily as a product for kommunal verksamhet to being an open Swedish prompt library for professional use. The landing page should reflect that shift without erasing the public-sector origin and trust bar.

The page should position Promptbanken for yrkespersoner och organisationer that want to use AI in a more structured, clear, and responsible way.

## Target Audience

Primary audience:

- Yrkespersoner och organisationer som skriver, planerar, analyserar eller utvecklar verksamhet med AI.

Secondary credibility audience:

- Kommuner, offentlig sektor, skola, civilsamhalle, foreningar and smaller organizations that need high trust, clear language, and careful handling of personal data.

Public sector should appear as proof of quality and responsibility, not as the full product identity.

## Tone

Use modern, direct product copy in Swedish:

- clear and concrete
- professional, but not myndighetstung
- serious without startup slogans
- focused on real work rather than AI novelty

Avoid overpromising. AI should be described as support for structure, language, first drafts, and workflows. The user remains responsible for review and judgment.

## Recommended Copy

### Metadata

Title:

> Promptbanken - svenska promptmallar for arbete med AI

Description:

> Ett oppet bibliotek med svenska promptmallar for tydligare texter, battre arbetsfloden och mer ansvarsfull AI-anvandning.

### Hero

Kicker:

> Oppet bibliotek for arbete med AI

H1:

> Svenska promptmallar for tydligare texter, battre arbetsfloden och sakrare AI-anvandning

Lead:

> Promptbanken hjalper yrkespersoner och organisationer att anvanda AI mer strukturerat. Hitta fardiga mallar for kommunikation, planering, analys och verksamhetsutveckling - anpassade for verkliga arbetsuppgifter.

Primary CTA:

> Hitta en prompt

Secondary CTA:

> Koppla till din AI-klient

### Trust Strip

Item 1:

> Oppet att anvanda
>
> Sok, oppna och kopiera mallar utan konto.

Item 2:

> Byggt for svenska arbetsuppgifter
>
> Mallar for texter, moten, checklistor, underlag och tydligare kommunikation.

Item 3:

> Ansvar fran borjan
>
> Promptarna paminner om att ta bort personuppgifter och granska AI-svar innan de anvands.

### Use Cases

Section heading:

> Kom vidare utan att borja fran ett tomt fonster

Intro:

> Valj en mall, anpassa den till uppgiften och anvand den i det AI-verktyg du redan arbetar med.

Cards:

> Skriv tydligare
>
> Gor texter mer begripliga, kortare eller battre anpassade till malgruppen.

> Strukturera arbete
>
> Skapa checklistor, motesunderlag, rutiner och sammanfattningar.

> Analysera och jamfor
>
> Fa stod for att vaga alternativ, hitta risker och formulera underlag.

> Utveckla verksamhet
>
> Anvand mallar for idearbete, forbattringar och aterkommande processer.

### Public Sector Credibility

Heading:

> Utvecklad med offentlig sektor som kvalitetskrav

Body:

> Promptbanken har vuxit fram ur behov i kommunal och offentlig verksamhet, dar tydlighet, ansvar och integritet ar viktiga fran borjan. Det gor biblioteket anvandbart aven for foretag, foreningar och andra organisationer som vill arbeta mer genomtankt med AI.

### MCP

Heading:

> Anvand Promptbanken dar du redan arbetar

Body:

> Du kan anvanda biblioteket direkt pa webben eller koppla Promptbanken till en AI-klient via MCP. Da kan AI-verktyget hitta relevanta mallar nar du arbetar med texter, underlag, checklistor eller planering.

CTA:

> Las hur MCP fungerar

## Scope

This design is copy-first. It does not require new backend work, Supabase changes, MCP changes, or account/product-tier changes.

Implementation should focus on `index.html` and only minimal CSS changes if the existing landing layout needs room for the new sections.

## Non-Goals

- Do not reintroduce Promptbanken as primarily a kommun product in the hero.
- Do not claim customer logos, testimonials, measured outcomes, or certifications that are not in the repo.
- Do not make Valvet or Pro the main landing-page offer.
- Do not describe AI as automatic decision-making.

## Acceptance Criteria

- The hero no longer says "Promptbanken for kommun".
- The first viewport communicates open Swedish prompt templates for professional AI work.
- Public sector remains visible as a quality/trust signal below the hero.
- The page still gives two clear paths: browse prompts on the web or connect through MCP.
- The wording remains Swedish, concrete, and suitable for a broad professional audience.
