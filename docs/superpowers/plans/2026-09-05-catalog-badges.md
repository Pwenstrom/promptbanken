# Ny/Trendande/Populär-badges i katalogen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ge varje katalogkort (prompter och paket) på `promptbanken.html`
en av tre badges — Ny, Trendande, Populär — beräknade nattetid från redan
existerande statistik i `library_usage_events`.

**Architecture:** Ett nytt nattligt pg_cron-jobb räknar ut badges en gång
per natt och skriver dem till en liten tabell (`catalog_badges`). En
publik läs-RPC (`list_catalog_badges`) returnerar hela tabellen i ett
anrop. Frontend (`script.js`) hämtar den listan parallellt med sina
befintliga katalog-RPC-anrop och renderar en badge i varje korts
tagg-rad. Ingen ny skrivväg för klienter — samma mönster som den
befintliga `purge_library_usage_events`-städningen.

**Tech Stack:** Supabase (Postgres, PL/pgSQL, pg_cron, PostgREST-RPC),
vanilla JavaScript (`script.js`, inga imports, laddas direkt i
`promptbanken.html`).

**Spec:** `docs/superpowers/specs/2026-09-05-catalog-badges-design.md`
— badge-definitioner, färger/ikoner (godkända via en designkanvas),
prioritetsordning.

## Global Constraints

- Rank-baserat (topp N), inte absoluta trösklar för Trendande/Populär —
  gränsen följer trafiken automatiskt.
- Prioritetsordning vid flera träffar: **Ny > Trendande > Populär**. Ett
  objekt bär högst en badge.
- Endast `status = 'published'`-rader i `catalog_prompts`/
  `catalog_packages` kan få en badge.
- Följ repots RPC-mönster: `app_private.<namn>` för skrivfunktioner,
  `public.<namn>` för läs-RPC:er, `revoke all ... from public` +
  explicit `grant execute ... to <roll>`.
- Legacy statiska prompter utan katalogtvilling får ingen badge — de
  finns inte i `catalog_prompts` alls, så de faller bort naturligt (ingen
  extra kod behövs för att utesluta dem).
- `npm run build` och `npm test` ska vara gröna efter varje JS-ändring.
- Ingen ändring i `mcp_promptbanken`-repot eller `/mcp`-ytan.

---

## File Structure

| Fil | Ansvar |
| --- | --- |
| `supabase/migrations/20260905140000_catalog_badges.sql` | Task 1: tabell, RLS, beräkningsfunktion, cron-schema, läs-RPC |
| `supabase/tests/verify_catalog_badges.sql` | Task 1: verifiering |
| `style.css` | Task 2: badge-CSS |
| `script.js` | Task 2 (prompt-kort), Task 3 (paket-kort) |

---

### Task 1: Databas — tabell, beräkning, schemaläggning, läs-RPC

**Files:**
- Create: `supabase/migrations/20260905140000_catalog_badges.sql`
- Create: `supabase/tests/verify_catalog_badges.sql`

**Interfaces:**
- Produces: `public.catalog_badges` (kolumner: `subject_type text`,
  `subject_slug text`, `badge text`, `computed_at timestamptz`, primary
  key `(subject_type, subject_slug)`). `app_private.
  recompute_catalog_badges() returns void` (anropas bara av pg_cron).
  `public.list_catalog_badges() returns table (subject_type text,
  subject_slug text, badge text)` — konsumeras av Task 2/3 i `script.js`.

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260905140000_catalog_badges.sql
-- Ny/Trendande/Populär-badges för katalogkort. Se
-- docs/superpowers/specs/2026-09-05-catalog-badges-design.md.
--
-- Beräknas nattetid från library_usage_events (20260729082734), inte
-- live vid varje sidladdning -- katalogen har inte behov av
-- sekundfärsk data, och en nattlig batch är billigare och enklare att
-- resonera om. Samma mönster som den redan schemalagda
-- purge_library_usage_events (03:15) -- badges räknas 02:30, en halvtimme
-- innan, så gårdagens fulla statistik alltid ligger kvar när badges
-- beräknas (utrensningen tar bara bort händelser äldre än 180 dagar,
-- vilket aldrig träffar 7/14/90-dagarsfönstren nedan -- ordningen är en
-- säkerhetsmarginal, inget krav).

-- 1. Tabell -----------------------------------------------------------

create table public.catalog_badges (
    subject_type text not null check (subject_type in ('prompt', 'package')),
    subject_slug text not null,
    badge text not null check (badge in ('new', 'trending', 'popular')),
    computed_at timestamptz not null default now(),
    primary key (subject_type, subject_slug)
);

alter table public.catalog_badges enable row level security;

create policy "catalog_badges_select_all"
    on public.catalog_badges for select
    to anon, authenticated
    using (true);

revoke all on public.catalog_badges from public;
grant select on public.catalog_badges to anon, authenticated;

-- 2. Beräkningsfunktion -------------------------------------------------
-- Ingen ägarskapskontroll behövs -- anropas bara av pg_cron nedan,
-- aldrig av en användare. Samma resonemang som
-- app_private.purge_library_usage_events().

create or replace function app_private.recompute_catalog_badges()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from public.catalog_badges;

    -- Ny: publicerad senaste 14 dagarna.
    insert into public.catalog_badges (subject_type, subject_slug, badge)
    select 'prompt', slug, 'new'
      from public.catalog_prompts
     where status = 'published'
       and created_at >= now() - interval '14 days'
    union all
    select 'package', slug, 'new'
      from public.catalog_packages
     where status = 'published'
       and created_at >= now() - interval '14 days';

    -- Trendande: senaste 7 dagarna >= 3x föregående 7 dagarna (dag 8-14),
    -- minst 3 händelser senaste 7 dagarna, topp 5 per typ, hoppar över
    -- redan "new".
    insert into public.catalog_badges (subject_type, subject_slug, badge)
    select 'prompt', t.slug, 'trending'
      from (
        select cp.slug,
               count(*) filter (where e.created_at >= now() - interval '7 days') as recent,
               count(*) filter (where e.created_at < now() - interval '7 days') as prior
          from public.catalog_prompts cp
          join public.library_usage_events e on e.prompt_slug = cp.slug
         where cp.status = 'published'
           and e.created_at >= now() - interval '14 days'
           and e.event_type in ('prompt_view', 'prompt_copy', 'prompt_get')
         group by cp.slug
      ) t
     where t.recent >= 3
       and t.recent >= 3 * t.prior
       and not exists (
             select 1 from public.catalog_badges b
              where b.subject_type = 'prompt' and b.subject_slug = t.slug
           )
     order by t.recent desc
     limit 5
    union all
    select 'package', t.slug, 'trending'
      from (
        select cpk.slug,
               count(*) filter (where e.created_at >= now() - interval '7 days') as recent,
               count(*) filter (where e.created_at < now() - interval '7 days') as prior
          from public.catalog_packages cpk
          join public.library_usage_events e on e.package_slug = cpk.slug
         where cpk.status = 'published'
           and e.created_at >= now() - interval '14 days'
           and e.event_type in ('package_view', 'package_get', 'package_prompts_list')
         group by cpk.slug
      ) t
     where t.recent >= 3
       and t.recent >= 3 * t.prior
       and not exists (
             select 1 from public.catalog_badges b
              where b.subject_type = 'package' and b.subject_slug = t.slug
           )
     order by t.recent desc
     limit 5;

    -- Populär: topp 10 prompter / topp 5 paket senaste 90 dagarna, minst
    -- 5 händelser, hoppar över redan "new"/"trending".
    insert into public.catalog_badges (subject_type, subject_slug, badge)
    select 'prompt', t.slug, 'popular'
      from (
        select cp.slug, count(*) as total
          from public.catalog_prompts cp
          join public.library_usage_events e on e.prompt_slug = cp.slug
         where cp.status = 'published'
           and e.created_at >= now() - interval '90 days'
           and e.event_type in ('prompt_view', 'prompt_copy', 'prompt_get')
         group by cp.slug
      ) t
     where t.total >= 5
       and not exists (
             select 1 from public.catalog_badges b
              where b.subject_type = 'prompt' and b.subject_slug = t.slug
           )
     order by t.total desc
     limit 10
    union all
    select 'package', t.slug, 'popular'
      from (
        select cpk.slug, count(*) as total
          from public.catalog_packages cpk
          join public.library_usage_events e on e.package_slug = cpk.slug
         where cpk.status = 'published'
           and e.created_at >= now() - interval '90 days'
           and e.event_type in ('package_view', 'package_get', 'package_prompts_list')
         group by cpk.slug
      ) t
     where t.total >= 5
       and not exists (
             select 1 from public.catalog_badges b
              where b.subject_type = 'package' and b.subject_slug = t.slug
           )
     order by t.total desc
     limit 5;
end;
$$;

revoke all on function app_private.recompute_catalog_badges() from public;

-- 3. Schemaläggning -----------------------------------------------------
-- pg_cron-extensionen finns redan (20260729082734_open_library_usage_events.sql).

select cron.unschedule(jobid)
  from cron.job
 where jobname = 'recompute-catalog-badges';

select cron.schedule(
    'recompute-catalog-badges',
    '30 2 * * *',
    $$select app_private.recompute_catalog_badges();$$
);

-- 4. Läs-RPC -------------------------------------------------------------

create or replace function public.list_catalog_badges()
returns table (subject_type text, subject_slug text, badge text)
language sql
stable
security definer
set search_path = ''
as $$
    select subject_type, subject_slug, badge from public.catalog_badges;
$$;

revoke all on function public.list_catalog_badges() from public;
grant execute on function public.list_catalog_badges() to anon, authenticated;
```

- [ ] **Step 2: Applicera migrationen**

Kör via `mcp__supabase__apply_migration` (namn: `catalog_badges`) eller
`supabase db push`.

- [ ] **Step 3: Skriv och kör verifieringen**

```sql
-- supabase/tests/verify_catalog_badges.sql
-- Self-contained, rollback-wrapped. Skapar fixture-prompter/paket och
-- library_usage_events-rader med kända tidsstämplar, kör
-- app_private.recompute_catalog_badges() direkt (ingen auth.uid()-koll i
-- funktionen -- den anropas bara av pg_cron, se kommentar i migrationen),
-- verifierar rätt badge per slug inklusive prioritetsordningen.

begin;

-- Fixture-prompter -------------------------------------------------------
insert into public.catalog_prompts (id, slug, status)
values
  ('a1000000-0000-0000-0000-000000000001', 'badge-fixture-new', 'published'),
  ('a1000000-0000-0000-0000-000000000002', 'badge-fixture-trending', 'published'),
  ('a1000000-0000-0000-0000-000000000003', 'badge-fixture-popular', 'published'),
  ('a1000000-0000-0000-0000-000000000004', 'badge-fixture-none', 'published'),
  ('a1000000-0000-0000-0000-000000000005', 'badge-fixture-new-and-trending', 'published');

update public.catalog_prompts set created_at = now() - interval '2 days'
 where slug in ('badge-fixture-new', 'badge-fixture-new-and-trending');
update public.catalog_prompts set created_at = now() - interval '60 days'
 where slug in ('badge-fixture-trending', 'badge-fixture-popular', 'badge-fixture-none');

insert into public.catalog_prompt_variants (prompt_id, context_key, title, summary, prompt_text)
values
  ('a1000000-0000-0000-0000-000000000001', 'generell', 'Ny', 'S', 'T'),
  ('a1000000-0000-0000-0000-000000000002', 'generell', 'Trendande', 'S', 'T'),
  ('a1000000-0000-0000-0000-000000000003', 'generell', 'Populär', 'S', 'T'),
  ('a1000000-0000-0000-0000-000000000004', 'generell', 'Ingen', 'S', 'T'),
  ('a1000000-0000-0000-0000-000000000005', 'generell', 'Ny och trendande', 'S', 'T');

-- badge-fixture-trending: 10 händelser senaste 7 dagarna, 1 föregående
-- 7 dagarna -> 10 >= 3*1, kvalificerar.
insert into public.library_usage_events (source, event_type, prompt_slug, created_at)
select 'web', 'prompt_view', 'badge-fixture-trending', now() - (n || ' hours')::interval
  from generate_series(1, 10) as n;
insert into public.library_usage_events (source, event_type, prompt_slug, created_at)
values ('web', 'prompt_view', 'badge-fixture-trending', now() - interval '10 days');

-- badge-fixture-popular: 20 händelser senaste 90 dagarna, men bara 1
-- senaste 7 dagarna (under trending-tröskeln) -> populär, inte trendande.
insert into public.library_usage_events (source, event_type, prompt_slug, created_at)
select 'web', 'prompt_copy', 'badge-fixture-popular', now() - (n || ' days')::interval
  from generate_series(10, 29) as n;

-- badge-fixture-none: bara 2 händelser totalt -> under alla trösklar.
insert into public.library_usage_events (source, event_type, prompt_slug, created_at)
values
  ('web', 'prompt_view', 'badge-fixture-none', now() - interval '1 day'),
  ('web', 'prompt_view', 'badge-fixture-none', now() - interval '2 days');

-- badge-fixture-new-and-trending: skulle kvalificera för trending också,
-- men "new" ska vinna (prioritetsordning).
insert into public.library_usage_events (source, event_type, prompt_slug, created_at)
select 'web', 'prompt_view', 'badge-fixture-new-and-trending', now() - (n || ' hours')::interval
  from generate_series(1, 10) as n;

-- Fixture-paket (ett per gren, för att bekräfta att paket-grenen körs) --
insert into public.catalog_packages (id, slug, status, package_type)
values
  ('a2000000-0000-0000-0000-000000000001', 'badge-fixture-pkg-new', 'published', 'collection'),
  ('a2000000-0000-0000-0000-000000000002', 'badge-fixture-pkg-popular', 'published', 'collection');
update public.catalog_packages set created_at = now() - interval '2 days'
 where slug = 'badge-fixture-pkg-new';
update public.catalog_packages set created_at = now() - interval '60 days'
 where slug = 'badge-fixture-pkg-popular';
insert into public.catalog_package_variants (package_id, context_key, title, summary, intro_text)
values
  ('a2000000-0000-0000-0000-000000000001', 'generell', 'Paket ny', 'S', 'I'),
  ('a2000000-0000-0000-0000-000000000002', 'generell', 'Paket populär', 'S', 'I');
insert into public.library_usage_events (source, event_type, package_slug, created_at)
select 'web', 'package_view', 'badge-fixture-pkg-popular', now() - (n || ' days')::interval
  from generate_series(10, 24) as n;

-- Kör beräkningen ---------------------------------------------------------
select app_private.recompute_catalog_badges();

do $$
declare
    v_badge text;
begin
    select badge into v_badge from public.catalog_badges
     where subject_type = 'prompt' and subject_slug = 'badge-fixture-new';
    if v_badge is distinct from 'new' then
        raise exception 'Expected new for badge-fixture-new, got %', v_badge;
    end if;

    select badge into v_badge from public.catalog_badges
     where subject_type = 'prompt' and subject_slug = 'badge-fixture-trending';
    if v_badge is distinct from 'trending' then
        raise exception 'Expected trending for badge-fixture-trending, got %', v_badge;
    end if;

    select badge into v_badge from public.catalog_badges
     where subject_type = 'prompt' and subject_slug = 'badge-fixture-popular';
    if v_badge is distinct from 'popular' then
        raise exception 'Expected popular for badge-fixture-popular, got %', v_badge;
    end if;

    select badge into v_badge from public.catalog_badges
     where subject_type = 'prompt' and subject_slug = 'badge-fixture-none';
    if v_badge is not null then
        raise exception 'Expected no badge for badge-fixture-none, got %', v_badge;
    end if;

    select badge into v_badge from public.catalog_badges
     where subject_type = 'prompt' and subject_slug = 'badge-fixture-new-and-trending';
    if v_badge is distinct from 'new' then
        raise exception 'Expected new (priority over trending) for badge-fixture-new-and-trending, got %', v_badge;
    end if;

    select badge into v_badge from public.catalog_badges
     where subject_type = 'package' and subject_slug = 'badge-fixture-pkg-new';
    if v_badge is distinct from 'new' then
        raise exception 'Expected new for badge-fixture-pkg-new, got %', v_badge;
    end if;

    select badge into v_badge from public.catalog_badges
     where subject_type = 'package' and subject_slug = 'badge-fixture-pkg-popular';
    if v_badge is distinct from 'popular' then
        raise exception 'Expected popular for badge-fixture-pkg-popular, got %', v_badge;
    end if;

    raise notice 'catalog badges: all 7 fixtures got the expected badge -- OK';
end $$;

-- list_catalog_badges() läser tillbaka samma rader anonymt.
set local role anon;
do $$
declare
    v_count integer;
begin
    select count(*) into v_count from public.list_catalog_badges()
     where subject_slug like 'badge-fixture-%';
    if v_count <> 6 then
        raise exception 'Expected 6 badged fixtures visible via list_catalog_badges(), got %', v_count;
    end if;
    raise notice 'list_catalog_badges: anon can read all 6 badged fixtures -- OK';
end $$;
reset role;

rollback;
```

Kör den och bekräfta att båda `raise notice`-raderna syns (inget fel
kastas i något DO-block).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260905140000_catalog_badges.sql supabase/tests/verify_catalog_badges.sql
git commit -m "feat(catalog): compute Ny/Trendande/Populär badges nightly from usage stats"
```

---

### Task 2: Frontend — badge på promptkort

**Files:**
- Modify: `script.js` (`loadCatalogPrompts()`, `createCatalogPromptCard()`,
  modulnivå-deklarationer runt `catalogAreaLabels`/`catalogRiskLabels`)
- Modify: `style.css`

**Interfaces:**
- Consumes: `public.list_catalog_badges()` (Task 1).
- Produces: modulnivå-`Map` `catalogPromptBadges` (nyckel: `prompt.id` —
  samma nyckel `createCatalogPromptCard` redan indexerar
  `catalogPromptsById` med, se `script.js:939`), konsumeras av Task 3
  (samma mönster, egen `catalogPackageBadges`-map).

- [ ] **Step 1: Lägg till badge-CSS**

```css
/* style.css -- lägg till direkt efter .risk-chip-reglerna (rad ~4538) */
.catalog-badge {
    display: inline-flex;
    align-items: center;
    gap: 0.3rem;
}

.catalog-badge[data-badge="new"] {
    background: #eef4ff !important;
    color: #0052a3 !important;
}

.catalog-badge[data-badge="trending"] {
    background: #f3e8ff !important;
    color: #7e22ce !important;
}

.catalog-badge[data-badge="popular"] {
    background: #fdf6e3 !important;
    color: #8a6d1d !important;
}
```

(`.card-tags span` -- som `.catalog-badge` matchar via `.card-tags`-
föräldern -- ger redan padding/border-radius/font-size/font-weight,
samma bas som `.risk-chip` redan återanvänder. `!important` matchar
`.risk-chip`s egna regler på raden ovanför, som redan har den
specificiteten mot `.card-tags span`.)

- [ ] **Step 2: Lägg till badge-etiketter och ikoner i script.js**

```javascript
// script.js -- lägg till direkt efter const catalogRiskLabels = ... (rad 772)
const catalogBadgeLabels = { new: 'Ny', trending: 'Trendande', popular: 'Populär' };
const catalogBadgeIcons = {
    new: '<svg class="badge-icon" width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2 L14.2 9.6 L22 12 L14.2 14.4 L12 22 L9.8 14.4 L2 12 L9.8 9.6 Z"/></svg>',
    trending: '<svg class="badge-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/></svg>',
    popular: '<svg class="badge-icon" width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 21 12 17.77 5.82 21 7 14.14 2 9.27l6.91-1.01L12 2z"/></svg>'
};
const catalogPromptBadges = new Map();

function catalogBadgeHtml(badge) {
    if (!badge || !catalogBadgeLabels[badge]) return '';
    return `<span class="catalog-badge risk-chip" data-badge="${badge}">${catalogBadgeIcons[badge]}${escapeHtml(catalogBadgeLabels[badge])}</span>`;
}
```

(Badgen återanvänder `.risk-chip`-klassen bara för pill-basen -- den
egna `.catalog-badge[data-badge=...]`-regeln från Step 1 vinner på
specificitet för färgen, exakt samma knep som `.risk-chip[data-risk*=...]`
redan gör mot bas-`.risk-chip`.)

- [ ] **Step 3: Hämta badges parallellt i `loadCatalogPrompts()`**

```javascript
// script.js -- loadCatalogPrompts(), ersätt raden
//   const prompts = await callCatalogRpc('list_published_prompts', {
//       p_context_keys: getActiveContextKeys()
//   });
// med:
        const [prompts, badgeRows] = await Promise.all([
            callCatalogRpc('list_published_prompts', {
                p_context_keys: getActiveContextKeys()
            }),
            callCatalogRpc('list_catalog_badges', {}).catch(() => [])
        ]);
        catalogPromptBadges.clear();
        (badgeRows || [])
            .filter((row) => row.subject_type === 'prompt')
            .forEach((row) => catalogPromptBadges.set(row.subject_slug, row.badge));
```

(Badge-anropet är non-fatal: `.catch(() => [])` gör att ett fel i
`list_catalog_badges` aldrig stoppar promptlistan -- korten renderas
precis som idag, bara utan badge. `subject_slug` matchar mot
`prompt.slug`, inte `prompt.id` -- badges nyckelas på slug i databasen
(Task 1), så uppslaget i Step 4 måste använda `prompt.slug`.)

- [ ] **Step 4: Rendera badgen i `createCatalogPromptCard()`**

```javascript
// script.js -- createCatalogPromptCard(prompt), lägg till bredvid de
// befintliga areaLabel/riskLabel-raderna (från den tidigare
// risk-chip-ändringen):
    const badgeHtml = catalogBadgeHtml(catalogPromptBadges.get(prompt.slug));
```

```javascript
// samma funktion, i card.innerHTML-mallen: lägg badgeHtml FÖRST i
// .card-tags-raden, före riskChip:
        <div class="card-tags">${badgeHtml}${riskChip}${audienceTag}</div>
```

- [ ] **Step 5: `npm run build` och manuell kontroll**

Bygg måste vara grönt. Manuellt (live, efter deploy): kör
`select app_private.recompute_catalog_badges();` en gång manuellt (som
gjordes för `share_referenced_package_items`-migrationen -- annars syns
inget förrän nattens cron körs), öppna `promptbanken.html`, bekräfta att
minst ett promptkort visar en badge och att den ligger före
risk-chippen i taggraden.

- [ ] **Step 6: Commit**

```bash
git add script.js style.css
git commit -m "feat(catalog): render Ny/Trendande/Populär badge on prompt cards"
```

---

### Task 3: Frontend — badge på paketkort

**Files:**
- Modify: `script.js` (`loadCatalogPackages()`, `createCatalogPackageCard()`)

**Interfaces:**
- Consumes: `catalogBadgeHtml()`, `catalogBadgeLabels`,
  `catalogBadgeIcons` (Task 2).
- Produces: modulnivå-`Map` `catalogPackageBadges` (nyckel: `pkg.slug`).

**Viktig skillnad mot Task 2:** paketkort saknar idag en
`.card-tags`-rad helt (`createCatalogPackageCard`, `script.js:1340-1361`
lägger `.catalog-package-type` som en fristående `<span>` under
brödtexten). Den här tasken lägger till en `.card-tags`-rad och flyttar
`.catalog-package-type` in i den, bredvid badgen -- ren layoutstädning,
ingen ändring av vad `.catalog-package-type` betyder eller styrs av.

- [ ] **Step 1: Hämta badges parallellt i `loadCatalogPackages()`**

```javascript
// script.js -- loadCatalogPackages(), samma mönster som Task 2 Step 3.
// Hitta raden som anropar list_published_packages (motsvarande
// loadCatalogPrompts-anropet, samma funktionsstruktur) och gör om den
// till:
        const [packages, badgeRows] = await Promise.all([
            callCatalogRpc('list_published_packages', {
                p_context_keys: getActiveContextKeys()
            }),
            callCatalogRpc('list_catalog_badges', {}).catch(() => [])
        ]);
        catalogPackageBadges.clear();
        (badgeRows || [])
            .filter((row) => row.subject_type === 'package')
            .forEach((row) => catalogPackageBadges.set(row.subject_slug, row.badge));
```

Lägg till `const catalogPackageBadges = new Map();` bredvid
`catalogPromptBadges` (Task 2, Step 2).

- [ ] **Step 2: Rendera badge + card-tags-rad i `createCatalogPackageCard()`**

```javascript
// script.js -- createCatalogPackageCard(pkg), lägg till innan
// card.innerHTML sätts:
    const badgeHtml = catalogBadgeHtml(catalogPackageBadges.get(pkg.slug));
```

```javascript
// samma funktion -- ersätt den fristående
//   <span class="catalog-package-type">${typeLabel}</span>
// raden i card.innerHTML med en card-tags-rad som rymmer båda:
        <div class="card-tags">
            ${badgeHtml}
            <span class="catalog-package-type">${typeLabel}</span>
        </div>
```

- [ ] **Step 3: `npm run build` och manuell kontroll**

Bygg måste vara grönt. Manuellt (live): efter samma nattliga/manuella
`recompute_catalog_badges()`-körning som Task 2, bekräfta att minst ett
paketkort visar en badge bredvid sin Samling/Arbetssätt-chip, och att
`.catalog-package-type`s egen styling (blå uppercase-chip) ser likadan
ut som innan flytten.

- [ ] **Step 4: Commit**

```bash
git add script.js
git commit -m "feat(catalog): render Ny/Trendande/Populär badge on package cards"
```

---

## Self-Review

**Spec coverage:** Badge-definitionerna (Ny/Trendande/Populär, tabellen
i specen) täcks av Task 1s beräkningsfunktion, rad för rad. Nattlig
beräkning (inte live) täcks av cron-schemat i Task 1. Prioritetsordning
Ny > Trendande > Populär täcks av `not exists`-villkoren i steg 2/3 av
funktionen och verifieras explicit av `badge-fixture-new-and-trending`
i Task 1s test. Färger/ikoner/placering (godkända via designkanvasen)
täcks av Task 2 Step 1-2 och Task 3 Step 2. Felhantering
(`list_catalog_badges`-fel ska aldrig stoppa katalogrendering) täcks av
`.catch(() => [])` i Task 2/3 Step 1. Paket-specifik card-tags-rad
(fanns inte innan) täcks av Task 3 Step 2.

**Placeholder-scan:** Ingen TBD kvar. All SQL och JS är komplett,
klistrbar -- inga "lägg till validering här" eller "liknande Task N".

**Typkonsekvens:** `catalog_badges`-kolumnerna (`subject_type`,
`subject_slug`, `badge`) matchar exakt mellan tabelldefinitionen,
`recompute_catalog_badges()`s inserts, `list_catalog_badges()`s
returtyp, och testets `select ... from public.list_catalog_badges()`.
`catalogPromptBadges`/`catalogPackageBadges` nycklas båda på `slug`
(inte `id`) genomgående i Task 2/3 -- kontrollerat mot att
`list_catalog_badges()` returnerar `subject_slug`, inte ett uuid, så
uppslaget i `createCatalogPromptCard`/`createCatalogPackageCard` måste
använda `prompt.slug`/`pkg.slug`, inte `.id`.
