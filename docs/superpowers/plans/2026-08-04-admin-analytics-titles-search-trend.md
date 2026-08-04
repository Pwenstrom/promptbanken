# Admin-analys: titlar, sökmissar, daglig trend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `admin.html`'s library analytics dashboard show real prompt/package titles instead of raw slugs, break down empty-search misses by context, and show a daily event trend — using data the RPCs already compute or can compute with a join, no new tracking.

**Architecture:** Three existing `security definer` RPCs (`get_library_prompt_usage`, `get_library_package_usage`, `get_library_usage_errors`) gain a `left join lateral` against the catalog tables to resolve a human title per slug, returned as new nullable output columns. `get_library_usage_summary`'s `daily` field and `get_library_search_feedback`'s `by_context` field already exist server-side; only the frontend (`src/adminUsage.js`, `admin.html`) needs to render them.

**Tech Stack:** PostgreSQL (Supabase migrations, `plpgsql`, `security definer`), vanilla JS (`src/adminUsage.js`, no framework, no bundler transform beyond Vite's default), static HTML (`admin.html`).

## Global Constraints

- No new eventtype, no new tracked field, `track_library_usage_event` unchanged (spec: Icke-mål).
- No RLS/throttling/retention changes (spec: Icke-mål).
- No chart library — plain tables, same markup style as existing dashboard sections (spec: Icke-mål).
- RPCs keep their existing signature (`p_days`, `p_limit`), same `security definer`, `set search_path = ''`, and `app_private.current_user_is_platform_owner()` guard as today — only the `returns table` column list and query body change.
- Missing/renamed catalog slug → title is `null` from SQL; frontend renders `"(borttagen — <slug>)"`. SQL never guesses (spec: Datakvalitet vid borttagen/omdöpt prompt).
- After any build step: `npm run build`, then confirm `dist/prompts/` still exists (project verification convention, `CLAUDE.md`).
- `script.js` and `src/adminUsage.js` are plain JS modules already in use — no new dependencies.

---

## File Structure

- **Create:** `supabase/migrations/20260804150000_library_usage_titles_and_trend.sql` — `create or replace` for the three RPCs, adding title columns via catalog joins.
- **Modify:** `supabase/tests/verify_library_usage_events.sql` — add manual verification steps for title resolution and the borttagen-fallback case.
- **Modify:** `src/adminUsage.js` — title fallback in `renderPromptUsage`/`renderPackageUsage`/`renderErrors`, new `renderSearchContext`, new `renderDailyTrend`, `exportCsv` gains title columns.
- **Modify:** `admin.html` — new table markup for the search-context breakdown and the daily trend.

---

### Task 1: Migration — title joins on prompt/package/error RPCs

**Files:**
- Create: `supabase/migrations/20260804150000_library_usage_titles_and_trend.sql`
- Modify: `supabase/tests/verify_library_usage_events.sql`

**Interfaces:**
- Produces: `get_library_prompt_usage(p_days integer, p_limit integer)` now returns `(prompt_slug text, prompt_title text, web_views integer, web_copies integer, mcp_gets integer, not_found integer, last_event_at timestamptz)`.
- Produces: `get_library_package_usage(p_days integer, p_limit integer)` now returns `(package_slug text, package_title text, web_views integer, mcp_gets integer, package_prompt_lists integer, not_found integer, last_event_at timestamptz)`.
- Produces: `get_library_usage_errors(p_days integer, p_limit integer)` now returns `(source text, event_type text, outcome text, prompt_slug text, prompt_title text, package_slug text, package_title text, count integer, last_event_at timestamptz)`.
- Consumes: existing tables `public.library_usage_events`, `public.catalog_prompts`, `public.catalog_prompt_variants`, `public.catalog_packages`, `public.catalog_package_variants` (all already exist per `supabase/migrations/20260721100000_catalog_core.sql` and `supabase/migrations/20260729082734_open_library_usage_events.sql`), and `app_private.current_user_is_platform_owner()`.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/20260804150000_library_usage_titles_and_trend.sql`:

```sql
-- supabase/migrations/20260804150000_library_usage_titles_and_trend.sql
-- Adds human-readable titles to the prompt/package/error usage RPCs by
-- joining catalog_prompts/catalog_packages + their variants. Titles are
-- null when the slug no longer resolves to a published catalog item
-- (renamed or deleted) — the frontend renders a "(borttagen — <slug>)"
-- fallback rather than the RPC guessing.

create or replace function public.get_library_prompt_usage(p_days integer default 30, p_limit integer default 50)
returns table (
    prompt_slug text,
    prompt_title text,
    web_views integer,
    web_copies integer,
    mcp_gets integer,
    not_found integer,
    last_event_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
    v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa biblioteksstatistik.';
    end if;

    return query
    select e.prompt_slug,
           title.title as prompt_title,
           count(*) filter (where e.source = 'web' and e.event_type = 'prompt_view')::int as web_views,
           count(*) filter (where e.source = 'web' and e.event_type = 'prompt_copy')::int as web_copies,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'prompt_get')::int as mcp_gets,
           count(*) filter (where e.outcome = 'not_found')::int as not_found,
           max(e.created_at) as last_event_at
      from public.library_usage_events e
      left join public.catalog_prompts cp on cp.slug = e.prompt_slug
      left join lateral (
        select v.title
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
         order by (v.context_key = 'generell') desc, v.created_at asc
         limit 1
      ) title on true
     where e.created_at >= now() - make_interval(days => v_days)
       and e.prompt_slug is not null
     group by e.prompt_slug, title.title
     order by (count(*) filter (where e.event_type in ('prompt_copy', 'prompt_get'))) desc,
              count(*) desc
     limit v_limit;
end;
$$;

revoke all on function public.get_library_prompt_usage(integer, integer) from public;
grant execute on function public.get_library_prompt_usage(integer, integer) to authenticated;

create or replace function public.get_library_package_usage(p_days integer default 30, p_limit integer default 50)
returns table (
    package_slug text,
    package_title text,
    web_views integer,
    mcp_gets integer,
    package_prompt_lists integer,
    not_found integer,
    last_event_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
    v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa biblioteksstatistik.';
    end if;

    return query
    select e.package_slug,
           title.title as package_title,
           count(*) filter (where e.source = 'web' and e.event_type = 'package_view')::int,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'package_get')::int,
           count(*) filter (where e.source = 'open_mcp' and e.event_type = 'package_prompts_list')::int,
           count(*) filter (where e.outcome = 'not_found')::int,
           max(e.created_at)
      from public.library_usage_events e
      left join public.catalog_packages cpk on cpk.slug = e.package_slug
      left join lateral (
        select v.title
          from public.catalog_package_variants v
         where v.package_id = cpk.id
         order by (v.context_key = 'generell') desc, v.created_at asc
         limit 1
      ) title on true
     where e.created_at >= now() - make_interval(days => v_days)
       and e.package_slug is not null
     group by e.package_slug, title.title
     order by count(*) desc
     limit v_limit;
end;
$$;

revoke all on function public.get_library_package_usage(integer, integer) from public;
grant execute on function public.get_library_package_usage(integer, integer) to authenticated;

create or replace function public.get_library_usage_errors(p_days integer default 30, p_limit integer default 50)
returns table (
    source text,
    event_type text,
    outcome text,
    prompt_slug text,
    prompt_title text,
    package_slug text,
    package_title text,
    count integer,
    last_event_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
    v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa biblioteksstatistik.';
    end if;

    return query
    select e.source, e.event_type, e.outcome, e.prompt_slug,
           prompt_title.title as prompt_title,
           e.package_slug,
           package_title.title as package_title,
           count(*)::int, max(e.created_at)
      from public.library_usage_events e
      left join public.catalog_prompts cp on cp.slug = e.prompt_slug
      left join lateral (
        select v.title
          from public.catalog_prompt_variants v
         where v.prompt_id = cp.id
         order by (v.context_key = 'generell') desc, v.created_at asc
         limit 1
      ) prompt_title on true
      left join public.catalog_packages cpk on cpk.slug = e.package_slug
      left join lateral (
        select v.title
          from public.catalog_package_variants v
         where v.package_id = cpk.id
         order by (v.context_key = 'generell') desc, v.created_at asc
         limit 1
      ) package_title on true
     where e.created_at >= now() - make_interval(days => v_days)
       and e.outcome in ('empty', 'not_found', 'invalid_input', 'rate_limited', 'error')
     group by e.source, e.event_type, e.outcome, e.prompt_slug, prompt_title.title, e.package_slug, package_title.title
     order by count(*) desc, max(e.created_at) desc
     limit v_limit;
end;
$$;

revoke all on function public.get_library_usage_errors(integer, integer) from public;
grant execute on function public.get_library_usage_errors(integer, integer) to authenticated;
```

- [ ] **Step 2: Add verification cases to the manual SQL test file**

Append to `supabase/tests/verify_library_usage_events.sql` (after the existing step 7, before the cleanup comment):

```sql
-- 9. As platform_owner: the test slug from Step 1/7 has no matching catalog_prompts
--    row, so prompt_title must be null (frontend renders the "(borttagen — slug)"
--    fallback, SQL does not guess).
select prompt_slug, prompt_title
  from public.get_library_prompt_usage(30, 10)
 where prompt_slug = 'testprompt';
-- Expected: one row, prompt_title is null.

-- 10. As platform_owner: pick any slug known to exist in catalog_prompts and confirm
--     prompt_title resolves to a real title, not the slug itself. Replace
--     '<real-published-slug>' with a slug from:
--     select slug from public.catalog_prompts where status = 'published' limit 1;
select prompt_slug, prompt_title
  from public.get_library_prompt_usage(365, 200)
 where prompt_slug = '<real-published-slug>';
-- Expected: prompt_title is non-null and differs from prompt_slug when the
-- catalog title differs from the slug (true for legacy-* seeded slugs).
```

- [ ] **Step 3: Run the migration locally or against staging**

Run: `supabase db push` (or apply via the Supabase MCP `apply_migration` tool against the linked/staging project, per project convention).

Expected: migration applies without error; the three functions are replaced.

- [ ] **Step 4: Run the verification file**

Run the queries in `supabase/tests/verify_library_usage_events.sql` (steps 1, 7, 9, 10 relevant here) against staging as platform_owner, using the SQL editor or `psql`.

Expected:
- Step 7/9: `testprompt` row returns with `prompt_title` null.
- Step 10: a real published slug returns a non-null, non-slug-shaped title.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260804150000_library_usage_titles_and_trend.sql supabase/tests/verify_library_usage_events.sql
git commit -m "feat(db): resolve prompt/package titles in library usage RPCs

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014EpQBktNytn8fZT2JAsLMW"
```

---

### Task 2: Frontend — show titles instead of raw slugs

**Files:**
- Modify: `src/adminUsage.js:63-113` (`renderPromptUsage`, `renderPackageUsage`, `renderErrors`)
- Modify: `src/adminUsage.js:215-223` (`exportCsv`)

**Interfaces:**
- Consumes: `prompt_title`, `package_title` fields now present on rows from `state.prompts`, `state.packages`, `state.errors` (Task 1).
- Produces: `promptLabel(row)`, `packageLabel(row)` helper functions other tasks/future work can reuse for consistent fallback text.

- [ ] **Step 1: Add title-fallback helpers**

In `src/adminUsage.js`, add after `formatDate` (currently ending at line 37):

```js
function promptLabel(row) {
  return row.prompt_title || `(borttagen — ${row.prompt_slug})`;
}

function packageLabel(row) {
  return row.package_title || `(borttagen — ${row.package_slug})`;
}
```

- [ ] **Step 2: Update `renderPromptUsage` to show the title**

Replace the existing `renderPromptUsage` function body:

```js
function renderPromptUsage() {
  const el = document.querySelector('[data-prompt-usage]');
  if (!el) return;
  el.innerHTML = state.prompts.length
    ? state.prompts.map((row) => `
      <tr>
        <td title="${escapeHtml(row.prompt_slug)}">${escapeHtml(promptLabel(row))}</td>
        <td>${row.web_views}</td>
        <td>${row.web_copies}</td>
        <td>${row.mcp_gets}</td>
        <td>${row.not_found}</td>
        <td>${formatDate(row.last_event_at)}</td>
      </tr>
    `).join('')
    : '<tr><td colspan="6">Ingen promptstatistik för vald period.</td></tr>';
}
```

- [ ] **Step 3: Update `renderPackageUsage` to show the title**

Replace the existing `renderPackageUsage` function body:

```js
function renderPackageUsage() {
  const el = document.querySelector('[data-package-usage]');
  if (!el) return;
  el.innerHTML = state.packages.length
    ? state.packages.map((row) => `
      <tr>
        <td title="${escapeHtml(row.package_slug)}">${escapeHtml(packageLabel(row))}</td>
        <td>${row.web_views}</td>
        <td>${row.mcp_gets}</td>
        <td>${row.package_prompt_lists}</td>
        <td>${row.not_found}</td>
        <td>${formatDate(row.last_event_at)}</td>
      </tr>
    `).join('')
    : '<tr><td colspan="6">Ingen paketstatistik för vald period.</td></tr>';
}
```

- [ ] **Step 4: Update `renderErrors` to show titles where a slug is present**

Replace the existing `renderErrors` function body:

```js
function renderErrors() {
  const el = document.querySelector('[data-usage-errors]');
  if (!el) return;
  el.innerHTML = state.errors.length
    ? state.errors.map((row) => `
      <tr>
        <td>${escapeHtml(row.source)}</td>
        <td>${escapeHtml(row.event_type)}</td>
        <td>${escapeHtml(row.outcome)}</td>
        <td title="${escapeHtml(row.prompt_slug || '')}">${row.prompt_slug ? escapeHtml(promptLabel(row)) : '-'}</td>
        <td title="${escapeHtml(row.package_slug || '')}">${row.package_slug ? escapeHtml(packageLabel(row)) : '-'}</td>
        <td>${row.count}</td>
        <td>${formatDate(row.last_event_at)}</td>
      </tr>
    `).join('')
    : '<tr><td colspan="7">Inga fel eller tomma utfall för vald period.</td></tr>';
}
```

- [ ] **Step 5: Add title columns to CSV export**

Replace the existing `exportCsv` function body:

```js
function exportCsv() {
  const rows = [
    ['type', 'slug', 'title', 'web_views', 'web_copies', 'mcp_gets', 'not_found', 'last_event_at'],
    ...state.prompts.map((row) => ['prompt', row.prompt_slug, row.prompt_title || '', row.web_views, row.web_copies, row.mcp_gets, row.not_found, row.last_event_at]),
    ...state.packages.map((row) => ['package', row.package_slug, row.package_title || '', row.web_views, '', row.mcp_gets, row.not_found, row.last_event_at])
  ];
  const csv = rows.map((row) => row.map((cell) => `"${String(cell ?? '').replaceAll('"', '""')}"`).join(',')).join('\n');
  downloadBlob(`promptbanken-statistik-${state.periodDays}d.csv`, csv, 'text/csv;charset=utf-8');
}
```

- [ ] **Step 6: Browser verification**

Run: `npm run web:dev`, sign in as platform_owner, open `admin.html`.

Expected: Prompts and Paket tables show real titles (e.g. a `legacy-*` slug now shows its catalog title, with the slug visible on hover via the `title` attribute); a slug with no matching catalog row (if any in test data) shows `(borttagen — <slug>)`. Export CSV includes a `title` column.

- [ ] **Step 7: Commit**

```bash
git add src/adminUsage.js
git commit -m "feat(web): show prompt/package titles in admin analytics tables

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014EpQBktNytn8fZT2JAsLMW"
```

---

### Task 3: Frontend — search miss breakdown by context

**Files:**
- Modify: `admin.html:73-76` (Sökningar section)
- Modify: `src/adminUsage.js:115-128` (`renderSearchFeedback`)

**Interfaces:**
- Consumes: `state.search.by_context` — array of `{ context_key: string, empty_count: number, total_count: number }`, already returned by `get_library_search_feedback` (`supabase/migrations/20260729082734_open_library_usage_events.sql:510-522`), already stored in `state.search` (`src/adminUsage.js:181`).
- Produces: `renderSearchContext()`, called from `renderSearchFeedback()`.

- [ ] **Step 1: Add the table markup to `admin.html`**

In `admin.html`, replace the Sökningar section (lines 73-76):

```html
                    <section class="workspace-section" id="sokningar">
                        <div class="workspace-section-heading"><h2>Sökningar och saknade behov</h2></div>
                        <div data-search-feedback></div>
                        <div class="workspace-table-wrap"><table class="workspace-table"><thead><tr><th>Kontext</th><th>Totalt</th><th>Utan träff</th><th>Missandel</th></tr></thead><tbody data-search-context></tbody></table></div>
                    </section>
```

- [ ] **Step 2: Add `renderSearchContext` and call it from `renderSearchFeedback`**

In `src/adminUsage.js`, replace the existing `renderSearchFeedback` function:

```js
function renderSearchFeedback() {
  const el = document.querySelector('[data-search-feedback]');
  if (!el) return;
  const searches = Number(state.search?.searches || 0);
  const empty = Number(state.search?.empty_searches || 0);
  const rate = searches ? Math.round((empty / searches) * 100) : 0;
  el.innerHTML = `
    <div class="library-insight-grid">
      <article><strong>${searches}</strong><span>Sökningar</span></article>
      <article><strong>${empty}</strong><span>Utan träff</span></article>
      <article><strong>${rate}%</strong><span>Tomma sökningar</span></article>
    </div>
  `;
  renderSearchContext();
}

function renderSearchContext() {
  const el = document.querySelector('[data-search-context]');
  if (!el) return;
  const rows = state.search?.by_context || [];
  el.innerHTML = rows.length
    ? rows.map((row) => {
        const total = Number(row.total_count || 0);
        const emptyCount = Number(row.empty_count || 0);
        const missRate = total ? Math.round((emptyCount / total) * 100) : 0;
        return `
          <tr>
            <td>${escapeHtml(row.context_key)}</td>
            <td>${total}</td>
            <td>${emptyCount}</td>
            <td>${missRate}%</td>
          </tr>
        `;
      }).join('')
    : '<tr><td colspan="4">Ingen sökdata för vald period.</td></tr>';
}
```

- [ ] **Step 3: Browser verification**

Run: `npm run web:dev`, open `admin.html` as platform_owner, click Sökningar.

Expected: a table below the three summary cards, one row per distinct `context_keys` combination seen in searches for the period, sorted by empty-count descending (inherited from the RPC's `order by c.empty_count desc`), with a computed miss percentage per row.

- [ ] **Step 4: Commit**

```bash
git add admin.html src/adminUsage.js
git commit -m "feat(web): break down empty searches by context in admin analytics

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014EpQBktNytn8fZT2JAsLMW"
```

---

### Task 4: Frontend — daily event trend

**Files:**
- Modify: `admin.html:47-59` (Översikt/`admin-hero` section)
- Modify: `src/adminUsage.js:142-149` (`renderAll`)

**Interfaces:**
- Consumes: `state.summary.daily` — array of `{ day: string, source: 'web' | 'open_mcp', events: number }`, already returned by `get_library_usage_summary` (`supabase/migrations/20260729082734_open_library_usage_events.sql:334-345`), already stored in `state.summary` (`src/adminUsage.js:177`).
- Produces: `renderDailyTrend()`, called from `renderAll()`.

- [ ] **Step 1: Add the trend table markup to `admin.html`**

In `admin.html`, insert a new table wrap right after the `admin-stat-grid` div (currently line 61, `<div class="admin-stat-grid" data-summary-cards></div>`):

```html
                    <div class="admin-stat-grid" data-summary-cards></div>

                    <section class="workspace-section" id="trend">
                        <div class="workspace-section-heading"><h2>Daglig trend</h2></div>
                        <div class="workspace-table-wrap"><table class="workspace-table"><thead><tr><th>Dag</th><th>Webb</th><th>Öppen MCP</th></tr></thead><tbody data-daily-trend></tbody></table></div>
                    </section>
```

- [ ] **Step 2: Add `renderDailyTrend` and call it from `renderAll`**

In `src/adminUsage.js`, add the function after `renderMcpStatus` (currently ending at line 140):

```js
function renderDailyTrend() {
  const el = document.querySelector('[data-daily-trend]');
  if (!el) return;
  const rows = state.summary?.daily || [];
  if (!rows.length) {
    el.innerHTML = '<tr><td colspan="3">Ingen trenddata för vald period.</td></tr>';
    return;
  }
  const byDay = new Map();
  rows.forEach((row) => {
    if (!byDay.has(row.day)) byDay.set(row.day, { web: 0, open_mcp: 0 });
    byDay.get(row.day)[row.source] = Number(row.events || 0);
  });
  const days = Array.from(byDay.keys()).sort();
  el.innerHTML = days.map((day) => {
    const counts = byDay.get(day);
    return `
      <tr>
        <td>${escapeHtml(day)}</td>
        <td>${counts.web || 0}</td>
        <td>${counts.open_mcp || 0}</td>
      </tr>
    `;
  }).join('');
}
```

Then update `renderAll` to call it:

```js
function renderAll() {
  renderSummary();
  renderDailyTrend();
  renderPromptUsage();
  renderPackageUsage();
  renderErrors();
  renderSearchFeedback();
  renderMcpStatus();
}
```

- [ ] **Step 3: Browser verification**

Run: `npm run web:dev`, open `admin.html` as platform_owner.

Expected: Översikt shows a "Daglig trend" table below the stat cards, one row per day in the selected period with events for that day present, columns Webb/Öppen MCP matching the totals visible elsewhere on the page. Switching the 7/30/90-day period control updates the table.

- [ ] **Step 4: Commit**

```bash
git add admin.html src/adminUsage.js
git commit -m "feat(web): add daily event trend table to admin analytics overview

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014EpQBktNytn8fZT2JAsLMW"
```

---

### Task 5: Build verification

**Files:**
- None (verification only).

**Interfaces:**
- Consumes: all changes from Tasks 1-4.

- [ ] **Step 1: Run the build**

Run: `npm run build`

Expected: exits 0.

- [ ] **Step 2: Confirm `dist/prompts/` survived the build**

Run: `ls dist/prompts` (or `Get-ChildItem dist/prompts` in PowerShell)

Expected: the directory exists and lists the same `.txt` files as `prompts/`.

- [ ] **Step 3: Final manual pass**

Reload `admin.html` against the build preview (`npm run preview`) or dev server, click through Översikt / Prompts / Paket / Sökningar / MCP-status / Export. Confirm no console errors, titles render, context breakdown renders, daily trend renders, CSV/JSON export still download.

- [ ] **Step 4: Commit (if anything needed fixing)**

```bash
git add -A
git commit -m "fix(web): address build/verification findings for admin analytics update

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014EpQBktNytn8fZT2JAsLMW"
```

Skip this commit if Steps 1-3 found nothing to fix.
