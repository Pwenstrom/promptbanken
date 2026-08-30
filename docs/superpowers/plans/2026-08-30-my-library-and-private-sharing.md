# Mitt bibliotek: referens, katalog-knapp och privat delning — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Koppla ihop Promptbankens öppna katalog med det privata biblioteket
(Valvet) via en riktig referensmodell (inte bara kopiering), lägg till en
synlig "Lägg till i mitt bibliotek"-knapp i huvudkatalogen, och generalisera
det befintliga creator-delningssystemet så en creator kan dela ett eget
opublicerat utkast privat, inte bara publicerat innehåll.

**Architecture:** Allt bygger vidare på befintlig, oförändrad datamodell
(`content_items`, `catalog_prompts`, `creator_shares`) med additiva
migrationer (nya nullbara kolumner, nya RPC:er, utökade check-constraints).
Inget i `mcp_promptbanken` eller Promptbanken Open MCP rörs. Arbetet spänner
två repon: `promptbanken` (Supabase-migrationer, katalogsidan, creator-ytan)
och `valvet_promptbanken` (Valvets frontend).

**Tech Stack:** Supabase (Postgres, PL/pgSQL, PostgREST-RPC), vanilla
JavaScript (`script.js`, ej modul), ES-moduler för `src/*.js` (Vite-bundlat),
`supabase-js` v2.

**Spec:** `docs/superpowers/specs/2026-08-30-connect-my-library-architecture-analysis.md`
(sektion F, G, H, E) — läs den innan du börjar, den motiverar varje
arkitekturval nedan.

## Global Constraints

- Promptbanken Open MCP 1.2.2 är fryst. Rör aldrig `mcp_promptbanken`-repot,
  `/mcp`-ytan, eller de fem katalog-läs-RPC:ernas signaturer
  (`list_published_prompts`, `get_published_prompt`, `list_published_packages`,
  `get_published_package`, `list_published_package_prompts`). Denna plan
  rör dem inte.
- Alla migrationer är additiva: nya kolumner är nullbara eller har säkra
  defaultvärden, nya RPC-parametrar har defaultvärden, inga befintliga
  kolumner byter betydelse.
- Följ repots namnmönster för RPC:er: `app_private.<namn>` för
  implementationen, `public.<namn>` som en tunn `security definer`-wrapper,
  `revoke all ... from public` + explicit `grant execute ... to authenticated`
  (eller `anon, authenticated` för publika läsvägar).
- All användarvänd text är på svenska, i samma ton som befintliga
  felmeddelanden ("Du måste vara inloggad.", inte "Unauthorized").
- Repot har ingen automatiserad testsvit för SQL eller frontend. Verifiering
  sker via körbara SQL-runbooks i `supabase/tests/verify_*.sql` (manuellt
  körda mot staging/länkad produktion, förväntat resultat som kommentar) och
  manuell webbläsarverifiering — samma mönster som varje befintlig fil i
  `supabase/tests/`. Skriv inga pytest/vitest-liknande automatiserade tester,
  de skulle inte matcha hur resten av repot verifieras.
- Ingen `window.prompt`/`window.confirm` i nytt UI. Destruktiva knappar
  kräver ett andra klick i knappen själv (samma mönster som
  `src/creatorShares.js`s `revokeBtn`).

---

## File Structure

| Fil | Repo | Ansvar |
| --- | --- | --- |
| `supabase/migrations/20260831090000_library_reference_prompts.sql` | promptbanken | Skapa: referenskolumn + `add_catalog_prompt_to_library` + `get_referenced_library_prompt` |
| `supabase/tests/verify_library_reference_prompts.sql` | promptbanken | Skapa: manuell verifieringsrunbook för Task 1 |
| `src/vault.js` | valvet_promptbanken | Ändra: rendera referensrader, ny "Lägg till som referens"-knapp, "Skapa egen version" |
| `supabase/migrations/20260831100000_library_add_usage_event.sql` | promptbanken | Skapa: nytt `library_add`-event för `track_library_usage_event` |
| `promptbanken.html` | promptbanken | Ändra: exponera `window.addPublishedPromptToLibrary`, filtrera "Mina prompter"-rälen |
| `script.js` | promptbanken | Ändra: ny knapp på katalogkort och i detaljpanelen |
| `supabase/migrations/20260831110000_creator_shares_private_content.sql` | promptbanken | Skapa: `list_my_shareable_content`, utökad `create_creator_share`/`build_content_payload`/`get_shared_content` |
| `supabase/tests/verify_creator_shares_private_content.sql` | promptbanken | Skapa: manuell verifieringsrunbook för Task 4 |
| `src/creatorShares.js` | promptbanken | Ändra: läs `list_my_shareable_content` istället för `list_creator_published_content` |
| `src/share.js` | promptbanken | Ändra: visa en "inte granskad"-banner när `reviewed === false` |
| `delning/index.html` | promptbanken | Ändra: lägg till bannerelementet |

---

### Task 1: Referensmodell — datalager

**Files:**
- Create: `supabase/migrations/20260831090000_library_reference_prompts.sql`
- Create: `supabase/migrations/20260831090500_library_reference_source_check.sql`
  (fixup — `content_items_source_check` tillät bara `'manual'`,
  `'chat_extraction'`, `'catalog_copy'`; `'catalog_reference'` saknades.
  Fångat av verifieringen i Step 4, se not efter Step 4.)
- Create: `supabase/tests/verify_library_reference_prompts.sql`

**Interfaces:**
- Produces: `public.add_catalog_prompt_to_library(p_prompt_id uuid) returns public.content_items` —
  anropas av Task 3. `public.get_referenced_library_prompt(p_content_item_id uuid, p_context_keys text[] default array['generell']) returns table(title text, summary text, prompt_text text, area text, risk_level text, security_examples text[])` —
  anropas av Task 2. Ny kolumn `content_items.library_ref_catalog_prompt_id uuid` —
  läses av Task 2 och Task 3.

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260831090000_library_reference_prompts.sql
-- "Lägg till i mitt bibliotek" som referens, inte kopia. Se
-- docs/superpowers/specs/2026-08-30-connect-my-library-architecture-analysis.md,
-- sektion F.
--
-- En referensrad i content_items har module='valvet', content='' (ingen
-- bakad prompttext) och library_ref_catalog_prompt_id satt till
-- källraden i catalog_prompts. Renderingslagret läser prompttexten live via
-- get_referenced_library_prompt istället för content_items.content.
-- source_template_id/source_version/source_copied_at (redan i bruk för
-- copy_published_prompt_to_valvet) sätts INTE på en referensrad -- de
-- betyder "kopierad vid den här tidpunkten", vilket är fel påstående om en
-- rad som medvetet ska följa originalet live.

alter table public.content_items
    add column if not exists library_ref_catalog_prompt_id uuid
        references public.catalog_prompts(id) on delete set null;

comment on column public.content_items.library_ref_catalog_prompt_id is
    'Satt när raden är en levande referens till en publicerad katalogprompt (inte en kopia). content är då tom sträng -- läs prompttexten via get_referenced_library_prompt(id), aldrig via content-kolumnen.';

create index if not exists content_items_library_ref_idx
    on public.content_items (library_ref_catalog_prompt_id)
    where library_ref_catalog_prompt_id is not null;

-- 1. Lägg till en referens -------------------------------------------------

create or replace function app_private.add_catalog_prompt_to_library(
    p_prompt_id uuid
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ws       public.workspaces%rowtype;
    v_existing public.content_items%rowtype;
    v_row      public.content_items%rowtype;
    v_slug     text;
    v_id       uuid;
    v_title    text;
    v_area     text;
begin
    if auth.uid() is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    select w.* into v_ws
      from public.workspaces w
      join public.profiles p on p.workspace_id = w.id
     where p.user_id = auth.uid()
       and w.type = 'personal'
       and w.status = 'active'
     order by p.created_at
     limit 1;

    if not found then
        raise exception 'Inget personligt workspace hittades.';
    end if;

    select cp.id, v.title, v.area
      into v_id, v_title, v_area
      from public.catalog_prompts cp
      join public.catalog_prompt_variants v
        on v.prompt_id = cp.id and v.context_key = 'generell'
     where cp.id = p_prompt_id
       and cp.status = 'published';

    if v_id is null then
        raise exception 'Den här mallen finns inte.';
    end if;

    -- Dubblettskydd: redan tillagd som referens och inte arkiverad -> returnera den.
    select * into v_existing
      from public.content_items
     where workspace_id = v_ws.id
       and module = 'valvet'
       and library_ref_catalog_prompt_id = v_id
       and status <> 'archived';

    if found then
        return v_existing;
    end if;

    v_slug := app_private.slugify_candidate(v_title, 'ref');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(v_title, 'ref') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility, source, library_ref_catalog_prompt_id
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id,
        'prompt'::public.content_item_type, 'valvet',
        v_title, v_slug, '', v_area,
        'draft', 'private', 'catalog_reference', v_id
    )
    returning * into v_row;

    return v_row;
end;
$$;

revoke all on function app_private.add_catalog_prompt_to_library(uuid) from public;

create or replace function public.add_catalog_prompt_to_library(p_prompt_id uuid)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.add_catalog_prompt_to_library(p_prompt_id);
$$;

revoke all on function public.add_catalog_prompt_to_library(uuid) from public;
grant execute on function public.add_catalog_prompt_to_library(uuid) to authenticated;

-- 2. Läs referensens live-innehåll -----------------------------------------

create or replace function public.get_referenced_library_prompt(
    p_content_item_id uuid,
    p_context_keys text[] default array['generell'::text]
)
returns table (
    title text,
    summary text,
    prompt_text text,
    area text,
    risk_level text,
    security_examples text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_catalog_id uuid;
begin
    select ci.library_ref_catalog_prompt_id
      into v_catalog_id
      from public.content_items ci
     where ci.id = p_content_item_id
       and ci.owner_user_id = auth.uid();

    if v_catalog_id is null then
        raise exception 'Ingen referens hittades för den här posten.';
    end if;

    return query
        select coalesce(matched.title, fallback.title),
               coalesce(matched.summary, fallback.summary),
               coalesce(matched.prompt_text, fallback.prompt_text),
               coalesce(matched.area, fallback.area),
               coalesce(matched.risk_level, fallback.risk_level),
               coalesce(matched.security_examples, fallback.security_examples)
          from public.catalog_prompts cp
          left join lateral (
              select v.* from public.catalog_prompt_variants v
               where v.prompt_id = cp.id and v.context_key = any(p_context_keys)
               order by array_position(p_context_keys, v.context_key)
               limit 1
          ) matched on true
          left join public.catalog_prompt_variants fallback
            on fallback.prompt_id = cp.id and fallback.context_key = 'generell'
         where cp.id = v_catalog_id
           and cp.status = 'published';
end;
$$;

revoke all on function public.get_referenced_library_prompt(uuid, text[]) from public;
grant execute on function public.get_referenced_library_prompt(uuid, text[]) to authenticated;
```

- [ ] **Step 2: Applicera migrationen mot staging/länkad produktion**

Kör: `supabase db push` (eller `mcp__supabase__apply_migration` om du kör
via MCP-verktyget). Bekräfta att `supabase db push --dry-run` visar
migrationen och inget annat väntande.

- [ ] **Step 3: Skriv verifieringsrunbooken**

```sql
-- supabase/tests/verify_library_reference_prompts.sql
-- Manuellt körbart end-to-end-flöde mot staging/länkad produktion.
-- Båda RPC:erna är auth.uid()-baserade -- kör som en inloggad testanvändare
-- (role impersonation, samma metod som verify_copy_published_prompt_to_valvet.sql).
--
-- Fixturer: en Free-personlig-workspace-testanvändare, och minst en
-- publicerad (status='published') catalog_prompts-rad med en 'generell'-
-- variant -- byt in dess riktiga id nedan.

-- 1. Lägg till en referens.
select * from public.add_catalog_prompt_to_library('<published-prompt-id>');
-- Förväntat: 1 rad. module='valvet', visibility='private', status='draft',
-- source='catalog_reference', content='', library_ref_catalog_prompt_id=
-- '<published-prompt-id>', source_template_id=null (INTE satt -- det fältet
-- betyder "kopierad", inte "refererad").

-- 2. Samma anrop igen -> dubblettskydd.
select * from public.add_catalog_prompt_to_library('<published-prompt-id>');
-- Förväntat: returnerar SAMMA rad (samma id) som steg 1. Ingen ny rad.

-- 3. Läs referensens live-innehåll. Använd id:t från steg 1.
select * from public.get_referenced_library_prompt('<content-item-id-från-steg-1>');
-- Förväntat: title/prompt_text/area matchar källpromptens 'generell'-variant.

-- 4. Läs en annan användares referens -> ska vägras.
-- Kör detta block inloggad som EN ANNAN testanvändare än steg 1-3.
select * from public.get_referenced_library_prompt('<content-item-id-från-steg-1>');
-- Förväntat: ERROR 'Ingen referens hittades för den här posten.'

-- 5. Opublicerad/okänd katalogprompt.
select * from public.add_catalog_prompt_to_library('<draft-or-missing-id>');
-- Förväntat: ERROR 'Den här mallen finns inte.'
```

- [ ] **Step 4: Kör runbooken mot staging och bekräfta varje förväntat resultat**

Dokumentera i PR-beskrivningen (eller commit-meddelandet) vilka verkliga
id:n du testade med och att alla fem stegen gav förväntat resultat.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260831090000_library_reference_prompts.sql supabase/tests/verify_library_reference_prompts.sql
git commit -m "feat(library): add reference model for catalog prompts"
```

---

### Task 2: Valvet — visa och hantera referensrader

**Files:**
- Modify: `valvet_promptbanken/src/vault.js:190-198` (`loadItems`)
- Modify: `valvet_promptbanken/src/vault.js:144-182` (`renderItemRow`)
- Modify: `valvet_promptbanken/src/vault.js:367-409` (`renderCatalogRow`, `copyToValvet`)

**Interfaces:**
- Consumes: `public.add_catalog_prompt_to_library(p_prompt_id uuid)`,
  `public.get_referenced_library_prompt(p_content_item_id uuid, p_context_keys text[])`,
  `public.copy_published_prompt_to_valvet(p_prompt_id uuid, p_context_keys text[])`
  (Task 1 och redan befintlig RPC).
- Produces: inget nytt för andra tasks — detta är UI-lagret.

- [ ] **Step 1: Inkludera referenskolumnen i `loadItems`**

I `valvet_promptbanken/src/vault.js:190-198`, byt select-listan:

```js
export async function loadItems() {
  const { data, error } = await supabase
    .from('content_items')
    .select('id, type, title, content, category, status, updated_at, library_ref_catalog_prompt_id')
    .eq('workspace_id', state.workspace.id)
    .eq('module', 'valvet')
    .eq('owner_user_id', state.user.id)
    .neq('status', 'archived')
    .order('updated_at', { ascending: false });

  if (error) {
    setErrorStatus('[data-item-list-empty]', error, 'Kunde inte ladda insättningar.');
    return;
  }

  state.items = data || [];
  renderItems();
}
```

- [ ] **Step 2: Visa referensbadge och byt ut knapparna på en referensrad**

Ersätt hela `renderItemRow` i `valvet_promptbanken/src/vault.js:144-182`:

```js
function renderItemRow(item, { showRestoreOnly = false } = {}) {
  const row = document.createElement('div');
  row.className = 'item-row';
  const isReference = Boolean(item.library_ref_catalog_prompt_id);
  const refBadge = isReference
    ? ' <span class="item-ref-badge">Följer original</span>'
    : '';
  row.innerHTML = `
    <div class="item-meta">
      <div class="item-title">${escapeHtml(item.title)} <span style="font-weight:400; color:var(--muted);">(${item.type === 'assistant' ? 'Assistent' : 'Prompt'})</span>${refBadge}</div>
      <div class="item-sub">${item.category ? escapeHtml(item.category) + ' — ' : ''}Ändrad ${new Date(item.updated_at).toLocaleString('sv-SE')}</div>
    </div>
    <div class="item-actions"></div>
  `;

  const actions = row.querySelector('.item-actions');

  if (showRestoreOnly) {
    const restoreBtn = document.createElement('button');
    restoreBtn.type = 'button';
    restoreBtn.className = 'secondary';
    restoreBtn.textContent = 'Återställ';
    restoreBtn.addEventListener('click', () => restoreItem(item));
    actions.appendChild(restoreBtn);
    return row;
  }

  if (isReference) {
    const viewBtn = document.createElement('button');
    viewBtn.type = 'button';
    viewBtn.className = 'secondary';
    viewBtn.textContent = 'Visa';
    viewBtn.addEventListener('click', () => openReferenceView(item));
    actions.appendChild(viewBtn);

    const forkBtn = document.createElement('button');
    forkBtn.type = 'button';
    forkBtn.className = 'secondary';
    forkBtn.textContent = 'Skapa egen version';
    forkBtn.addEventListener('click', () => forkReference(forkBtn, item));
    actions.appendChild(forkBtn);
  } else {
    const editBtn = document.createElement('button');
    editBtn.type = 'button';
    editBtn.className = 'secondary';
    editBtn.textContent = 'Redigera';
    editBtn.addEventListener('click', () => openItemForm(item));
    actions.appendChild(editBtn);
  }

  const archiveBtn = document.createElement('button');
  archiveBtn.type = 'button';
  archiveBtn.className = 'danger';
  archiveBtn.textContent = 'Arkivera';
  archiveBtn.addEventListener('click', () => confirmThenArchive(archiveBtn, item));
  actions.appendChild(archiveBtn);

  return row;
}
```

- [ ] **Step 3: Lägg till `openReferenceView` och `forkReference`**

Lägg till strax efter `openItemForm`/`closeItemForm` i
`valvet_promptbanken/src/vault.js` (efter rad 252):

```js
async function openReferenceView(item) {
  switchView('mina');
  document.querySelector('[data-item-form-card]').hidden = false;
  document.querySelector('[data-item-form-title]').textContent = 'Följer original (skrivskyddad)';
  document.querySelector('[data-item-id]').value = item.id;
  document.querySelector('[data-item-type]').value = item.type;
  document.querySelector('[data-item-title]').value = item.title;
  document.querySelector('[data-item-category]').value = item.category ?? '';
  document.querySelector('[data-item-content]').value = 'Hämtar innehåll...';
  document.querySelector('[data-item-content]').disabled = true;
  editingItemId = null; // referensen kan aldrig sparas via saveItem

  const { data, error } = await supabase.rpc('get_referenced_library_prompt', {
    p_content_item_id: item.id
  });

  if (error || !data || !data.length) {
    document.querySelector('[data-item-content]').value = 'Originalet kunde inte hämtas. Det kan ha avpublicerats.';
    return;
  }

  document.querySelector('[data-item-content]').value = data[0].prompt_text || '';
}

async function forkReference(button, item) {
  button.disabled = true;
  const original = button.textContent;
  button.textContent = 'Skapar...';

  const { error } = await supabase.rpc('copy_published_prompt_to_valvet', {
    p_prompt_id: item.library_ref_catalog_prompt_id
  });

  button.disabled = false;
  button.textContent = original;

  if (error) {
    setErrorStatus('[data-item-list-empty]', error, 'Kunde inte skapa en egen version.');
    return;
  }

  await Promise.all([loadItems(), refreshUsage()]);
}
```

Notera: `document.querySelector('[data-item-content]').disabled = true` gör
fältet skrivskyddat i vy-läge. Lägg till motsvarande `disabled = false` i
`openItemForm` (rad ~244, direkt efter `document.querySelector('[data-item-content]').value = ...`)
så vanlig redigering inte av misstag ärver det skrivskyddade läget:

```js
document.querySelector('[data-item-content]').value = item?.content ?? '';
document.querySelector('[data-item-content]').disabled = false;
```

- [ ] **Step 4: Lägg till "Lägg till som referens"-knappen i katalogbläddringen**

Ersätt `renderCatalogRow` i `valvet_promptbanken/src/vault.js:367-390`:

```js
function renderCatalogRow(item) {
  const row = document.createElement('div');
  row.className = 'item-row';
  const metaParts = [];
  if (item.area) metaParts.push(escapeHtml(item.area));
  if (item.risk_level) metaParts.push(escapeHtml(RISK_LABELS[item.risk_level] || item.risk_level));
  row.innerHTML = `
    <div class="item-meta">
      <div class="item-title">${escapeHtml(item.title)}</div>
      <div class="item-sub">${metaParts.length ? metaParts.join(' — ') + ' — ' : ''}${escapeHtml(item.summary || '')}</div>
    </div>
    <div class="item-actions"></div>
  `;

  const actions = row.querySelector('.item-actions');

  const refBtn = document.createElement('button');
  refBtn.type = 'button';
  refBtn.className = 'secondary';
  refBtn.textContent = 'Lägg till som referens';
  refBtn.addEventListener('click', () => addAsReference(refBtn, item));
  actions.appendChild(refBtn);

  const copyBtn = document.createElement('button');
  copyBtn.type = 'button';
  copyBtn.className = 'secondary';
  copyBtn.textContent = 'Skapa egen version';
  copyBtn.addEventListener('click', () => copyToValvet(copyBtn, item));
  actions.appendChild(copyBtn);

  return row;
}

async function addAsReference(button, item) {
  button.disabled = true;
  const originalText = button.textContent;
  button.textContent = 'Lägger till...';

  const { error } = await supabase.rpc('add_catalog_prompt_to_library', { p_prompt_id: item.id });

  button.disabled = false;
  button.textContent = originalText;

  if (error) {
    setErrorStatus('[data-catalog-status]', error, 'Kunde inte lägga till referensen.');
    return;
  }

  setStatus('[data-catalog-status]', `"${item.title}" tillagd som referens i ditt valv.`);
  await Promise.all([loadItems(), refreshUsage()]);
}
```

`copyToValvet` (rad 392-409) är oförändrad — bara döpt om i knapptexten
("Skapa egen version" istället för "Kopiera till mitt Valv", eftersom det
nu finns två olika sätt att lägga till samma katalogprompt och texten måste
skilja dem åt).

- [ ] **Step 5: Manuell webbläsarverifiering**

I `vault.html`, fliken "Bläddra i Promptbanken":
1. Klicka "Lägg till som referens" på en katalogprompt. Bekräfta att den
   dyker upp under "Mina insättningar" med badgen "Följer original".
2. Klicka "Visa" på den raden. Bekräfta att prompttexten visas (hämtad
   live) och att textrutan är skrivskyddad.
3. Klicka "Skapa egen version" på samma rad. Bekräfta att en ANDRA rad
   skapas (utan badge), redigerbar som vanligt.
4. Klicka "Arkivera" på referensraden. Bekräfta att den försvinner från
   listan precis som en vanlig insättning.
5. Klicka "Skapa egen version" (den gamla "Kopiera till mitt Valv") direkt
   från katalogbläddringen utan att först lägga till som referens. Bekräfta
   att det fortfarande fungerar precis som innan denna ändring.

- [ ] **Step 6: Commit**

```bash
git add src/vault.js
git commit -m "feat(vault): show and manage catalog reference items"
```

---

### Task 3: Katalogsidan — "Lägg till i mitt bibliotek"

**Files:**
- Modify: `promptbanken.html:567-714` (modulscriptet med `supabase`-klienten)
- Modify: `script.js:747-776` (`createCatalogPromptCard`)
- Modify: `script.js:914-970` (`renderCatalogDetailVariant`)
- Create: `supabase/migrations/20260831100000_library_add_usage_event.sql`

**Interfaces:**
- Consumes: `public.add_catalog_prompt_to_library(p_prompt_id uuid)` (Task 1).
- Produces: `window.addPublishedPromptToLibrary(promptId: string, button: HTMLButtonElement): Promise<void>` —
  globalt, anropas från `script.js` (icke-modul).

- [ ] **Step 1: Ny statistiktyp för "lägg till i biblioteket"**

```sql
-- supabase/migrations/20260831100000_library_add_usage_event.sql
-- Lägger till 'library_add' som tillåtet event_type för
-- track_library_usage_event, samma mönster som 'prompt_share'
-- (20260818090000_library_usage_prompt_share_event.sql). Skiljer sig
-- avsiktligt från 'prompt_copy' (urklipp) -- detta är en sparad rad i
-- användarens bibliotek, inte en engångskopiering.

alter table public.library_usage_events
    drop constraint if exists library_usage_event_type_check;

alter table public.library_usage_events
    add constraint library_usage_event_type_check
      check (event_type in (
        'prompt_view', 'prompt_copy', 'prompt_get', 'prompt_list', 'prompt_share', 'library_add',
        'package_view', 'package_get', 'package_list', 'package_prompts_list',
        'package_share', 'package_page_view',
        'search', 'filter_apply', 'error'
      ));

create or replace function public.track_library_usage_event(
    p_source text,
    p_event_type text,
    p_outcome text default 'success',
    p_prompt_slug text default null,
    p_package_slug text default null,
    p_context_keys text[] default null,
    p_area text default null,
    p_risk_level text default null,
    p_result_count integer default null,
    p_catalog_version text default null,
    p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
    v_context_keys text[];
begin
    if p_source not in ('web', 'open_mcp') then
        raise exception 'Ogiltig statistikkälla.';
    end if;

    if p_event_type not in (
        'prompt_view', 'prompt_copy', 'prompt_get', 'prompt_list', 'prompt_share', 'library_add',
        'package_view', 'package_get', 'package_list', 'package_prompts_list',
        'package_share', 'package_page_view',
        'search', 'filter_apply', 'error'
    ) then
        raise exception 'Ogiltig statistiktyp.';
    end if;

    if coalesce(p_outcome, 'success') not in ('success', 'empty', 'not_found', 'invalid_input', 'rate_limited', 'error') then
        raise exception 'Ogiltigt statistikutfall.';
    end if;

    if jsonb_typeof(v_metadata) <> 'object' or not app_private.library_usage_allowed_metadata(v_metadata) then
        raise exception 'Ogiltig statistikmetadata.';
    end if;

    if not app_private.library_usage_safe_slug(nullif(trim(coalesce(p_prompt_slug, '')), ''), 120)
       or not app_private.library_usage_safe_slug(nullif(trim(coalesce(p_package_slug, '')), ''), 120) then
        raise exception 'Ogiltig katalogslug.';
    end if;

    if p_area is not null and trim(p_area) not in (
        'kommunikation', 'forandringsledning', 'processer', 'beslutsberedning',
        'visuellt', 'ledarskap', 'arbetsbank',
        'Skriva och förbättra text', 'Svara och kommunicera',
        'Sammanfatta och strukturera', 'Möten och workshops',
        'Beslut och rutiner', 'Bilder och infografik'
    ) then
        raise exception 'Ogiltigt statistikområde.';
    end if;

    if p_risk_level is not null and trim(p_risk_level) not in (
        'low', 'medium', 'high', 'Låg risk', 'Medelrisk', 'Hög risk'
    ) then
        raise exception 'Ogiltig risknivå.';
    end if;

    if p_catalog_version is not null
       and trim(p_catalog_version) !~ '^[0-9]{1,10}$' then
        raise exception 'Ogiltig katalogversion.';
    end if;

    if exists (
        select 1
          from unnest(coalesce(p_context_keys, '{}'::text[])) as values(value)
         where trim(value) <> ''
           and trim(value) not in ('generell', 'kommun', 'skola', 'företag', 'förening', 'privat')
    ) then
        raise exception 'Ogiltig statistikkontext.';
    end if;

    select case
        when p_context_keys is null then null
        else (
            select array_agg(left(trim(limited.value), 40) order by limited.ordinality)
              from (
                select value, ordinality
                  from unnest(p_context_keys) with ordinality as values(value, ordinality)
                 where trim(value) <> ''
                 limit 10
              ) as limited
        )
    end into v_context_keys;

    insert into public.library_usage_events (
        source, event_type, outcome, prompt_slug, package_slug,
        context_keys, area, risk_level, result_count, catalog_version, metadata
    ) values (
        p_source, p_event_type, coalesce(p_outcome, 'success'),
        nullif(trim(coalesce(p_prompt_slug, '')), ''),
        nullif(trim(coalesce(p_package_slug, '')), ''),
        v_context_keys,
        nullif(trim(coalesce(p_area, '')), ''),
        nullif(trim(coalesce(p_risk_level, '')), ''),
        p_result_count,
        nullif(trim(coalesce(p_catalog_version, '')), ''),
        v_metadata
    );

    return jsonb_build_object('accepted', true);
end;
$$;

grant execute on function public.track_library_usage_event(
    text, text, text, text, text, text[], text, text, integer, text, jsonb
) to anon, authenticated;
```

Applicera med `supabase db push`, precis som Task 1 Step 2.

- [ ] **Step 2: Exponera en global handler i `promptbanken.html`s modulscript**

I `promptbanken.html`, direkt efter `loadMyPrompts()`s stängande brace
(efter rad 714, före `async function loadProTemplates()`):

```js
window.addPublishedPromptToLibrary = async function (promptId, button) {
  const { data: sessionData } = await supabase.auth.getSession();
  const session = sessionData?.session;

  if (!session) {
    window.location.href = 'login.html?redirect=promptbanken.html';
    return;
  }

  const original = button.textContent;
  button.disabled = true;
  button.textContent = 'Lägger till...';

  const { error } = await supabase.rpc('add_catalog_prompt_to_library', { p_prompt_id: promptId });

  button.disabled = false;

  if (error) {
    console.error('Kunde inte lägga till i biblioteket', error);
    button.textContent = 'Kunde inte lägga till';
    setTimeout(() => { button.textContent = original; }, 2500);
    return;
  }

  button.textContent = 'Tillagd ✓';
  setTimeout(() => { button.textContent = original; }, 2500);
};
```

- [ ] **Step 3: Uteslut referensrader från "Mina prompter"-rälen**

I `promptbanken.html`, i `loadMyPrompts()` (rad 674-678), lägg till ett
filter så rälen bara visar egna redigerbara rader, inte
bibliotekreferenser (de hör hemma i Valvet, inte i katalogsidans
snabbräl):

```js
const { data: items, error: itemsError } = await supabase
  .from('content_items')
  .select('id, title, summary, content, status, visibility, category, audience, risk_level, updated_at')
  .eq('workspace_id', profile.workspace_id)
  .is('library_ref_catalog_prompt_id', null)
  .order('updated_at', { ascending: false });
```

- [ ] **Step 4: Lägg till knappen på katalogkortet**

I `script.js:747-776`, byt `createCatalogPromptCard`:

```js
function createCatalogPromptCard(prompt) {
    const card = document.createElement('div');
    card.className = 'catalog-card';
    card.dataset.catalogPromptSlug = prompt.slug;
    card.dataset.catalogPromptId = prompt.id;
    const title = escapeHtml(prompt.title);
    const summary = escapeHtml(prompt.summary);
    const fallbackBadge = prompt.isFallback
        ? `<span class="catalog-context-badge">${escapeHtml(prompt.fallbackLabel || 'Kan vara generell version')}</span>`
        : '';
    card.innerHTML = `
        <h4>${title}</h4>
        <p>${summary}</p>
        ${fallbackBadge}
        <div class="catalog-card-actions">
            <button type="button" class="primary-btn catalog-select-btn">Välj</button>
            <button type="button" class="secondary-btn catalog-preview-btn">Förhandsvisa</button>
            <button type="button" class="secondary-btn catalog-library-btn">Lägg till i mitt bibliotek</button>
        </div>
    `;
    card.addEventListener('click', () => selectCatalogPromptInSidebar(prompt));
    card.querySelector('.catalog-select-btn').addEventListener('click', (event) => {
        event.stopPropagation();
        selectCatalogPromptInSidebar(prompt);
    });
    card.querySelector('.catalog-preview-btn').addEventListener('click', (event) => {
        event.stopPropagation();
        openCatalogPromptDetail(prompt.slug);
    });
    card.querySelector('.catalog-library-btn').addEventListener('click', (event) => {
        event.stopPropagation();
        window.addPublishedPromptToLibrary?.(prompt.id, event.currentTarget);
        trackLibraryUsageEvent({ eventType: 'library_add', promptSlug: prompt.slug });
    });
    return card;
}
```

- [ ] **Step 5: Lägg till knappen i detaljpanelen**

I `script.js:914-970`, `renderCatalogDetailVariant`, lägg till knappen i
`introOrPromptHtml`s prompt-gren och wira den efter `body.innerHTML = ...`:

```js
const introOrPromptHtml = isPrompt
    ? `<pre class="catalog-detail-prompt-text">${escapeHtml(renderCatalogTemplateField(normalizedVariant, 'prompt_text'))}</pre>
       <div class="catalog-card-actions">
           <button type="button" class="catalog-copy-btn" id="catalog-detail-copy-btn">Kopiera prompt</button>
           <button type="button" class="secondary-btn" id="catalog-detail-library-btn">Lägg till i mitt bibliotek</button>
       </div>`
    : (normalizedVariant.intro_text
        ? `<p>${escapeHtml(renderCatalogTemplateField(normalizedVariant, 'intro_text'))}</p>`
        : '');
```

Och i samma funktion, direkt efter blocket som wirar `catalog-detail-copy-btn`
(befintlig kod, rad 956-960):

```js
if (isPrompt) {
    document.getElementById('catalog-detail-copy-btn')?.addEventListener('click', (event) => {
        copyCatalogEntityText(normalizedVariant, event.currentTarget);
    });
    document.getElementById('catalog-detail-library-btn')?.addEventListener('click', (event) => {
        window.addPublishedPromptToLibrary?.(normalizedVariant.id, event.currentTarget);
        trackLibraryUsageEvent({ eventType: 'library_add', promptSlug: normalizedVariant.slug });
    });
}
```

- [ ] **Step 6: Manuell webbläsarverifiering**

1. Utloggad: klicka "Lägg till i mitt bibliotek" på ett katalogkort.
   Bekräfta att sidan navigerar till `login.html?redirect=promptbanken.html`.
2. Inloggad: klicka samma knapp. Bekräfta att knapptexten kort visar
   "Lägger till...", sedan "Tillagd ✓", och återgår efter ~2,5 sekunder.
3. Öppna Valvet (`valvet.promptbanken.se`) med samma konto. Bekräfta att
   prompten dykt upp under "Mina insättningar" med badgen "Följer
   original" (Task 2).
4. Upprepa via detaljpanelens knapp (öppna "Förhandsvisa" på en prompt,
   klicka knappen där). Samma resultat.
5. Kontrollera nätverksfliken: ett `library_add`-anrop mot
   `track_library_usage_event` syns, ingen konsolfel.
6. Skapa en egen prompt i Creator-ytan (module='kommun'). Bekräfta att den
   fortfarande syns i "Mina prompter"-rälen på `promptbanken.html` (steg 3
   ska bara utesluta referensrader, inte creator-innehåll).

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260831100000_library_add_usage_event.sql promptbanken.html script.js
git commit -m "feat(catalog): add 'add to my library' button"
```

---

### Task 4: Generalisera delningar till opublicerat eget innehåll

**Files:**
- Create: `supabase/migrations/20260831110000_creator_shares_private_content.sql`
- Create: `supabase/migrations/20260831110500_create_creator_share_gen_random_bytes_fix.sql`
  (fixup — uncovered a PRE-EXISTING production bug, not introduced by this
  task: the original `create_creator_share` (`20260825090000`) called
  `gen_random_bytes(16)` unqualified under `set search_path = ''`.
  pgcrypto lives in the `extensions` schema, so every call — for
  published content too — has failed since 2026-08-25 with "function
  gen_random_bytes(integer) does not exist". Caught by the rollback-
  wrapped verification in Step 3/4.)
- Create: `supabase/tests/verify_creator_shares_private_content.sql`
- Modify: `src/creatorShares.js:33-68` (`loadSubjects`)
- Modify: `src/share.js` (banner för ogranskat innehåll)
- Modify: `delning/index.html` (bannerelement)

**Interfaces:**
- Consumes: `public.creator_shares` (utökad `subject_type`-check), Task 1
  berörs inte av denna task.
- Produces: `public.list_my_shareable_content() returns table(kind text, subject_id uuid, title text, status_label text)` —
  konsumeras av `src/creatorShares.js`. `get_shared_content`s jsonb-svar
  får ett nytt fält `reviewed boolean` — konsumeras av `src/share.js`.

- [ ] **Step 1: Skriv migrationen**

```sql
-- supabase/migrations/20260831110000_creator_shares_private_content.sql
-- Generaliserar creator_shares till att omfatta eget opublicerat innehåll
-- (utkast och innehåll under granskning), inte bara publicerat
-- katalog-innehåll. Se
-- docs/superpowers/specs/2026-08-30-connect-my-library-architecture-analysis.md,
-- sektion E och H.
--
-- Två nya subject_type-värden: 'draft_prompt' (pekar på content_items.id,
-- module='kommun') och 'package_draft' (pekar på creator_package_drafts.id).
-- Ägarskapskontrollen för dessa är owner_user_id = auth.uid() direkt --
-- ingen creator_profile_id-koppling behövs eftersom innehållet aldrig
-- passerat granskningen och alltså inte ligger i katalogen än.

alter table public.creator_shares
    drop constraint if exists creator_shares_subject_type_check;

alter table public.creator_shares
    add constraint creator_shares_subject_type_check
      check (subject_type in ('prompt', 'package', 'draft_prompt', 'package_draft'));

-- 1. build_content_payload: två nya grenar --------------------------------

create or replace function app_private.build_content_payload(
    p_subject_type text,
    p_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_payload jsonb;
begin
    if p_subject_type = 'prompt' then
        select jsonb_build_object(
                   'kind', 'prompt',
                   'slug', cp.slug,
                   'title', v.title,
                   'summary', v.summary,
                   'prompt_text', v.prompt_text,
                   'example_input', v.example_input,
                   'audience_label', v.audience_label,
                   'tone_hint', v.tone_hint,
                   'risk_level', v.risk_level,
                   'security_examples', to_jsonb(coalesce(v.security_examples, array[]::text[]))
               )
          into v_payload
          from public.catalog_prompts cp
          join public.catalog_prompt_variants v
            on v.prompt_id = cp.id and v.context_key = 'generell'
         where cp.id = p_subject_id and cp.status = 'published';

    elsif p_subject_type = 'package' then
        select jsonb_build_object(
                   'kind', 'package',
                   'slug', cpkg.slug,
                   'package_type', cpkg.package_type,
                   'title', v.title,
                   'summary', v.summary,
                   'intro_text', v.intro_text,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'title', pv.title,
                                  'summary', pv.summary,
                                  'prompt_text', pv.prompt_text
                              ) order by cpi.sort_order)
                         from public.catalog_package_items cpi
                         join public.catalog_prompts p on p.id = cpi.prompt_id
                         join public.catalog_prompt_variants pv
                           on pv.prompt_id = p.id and pv.context_key = 'generell'
                        where cpi.package_id = cpkg.id and p.status = 'published'
                   ), '[]'::jsonb)
               )
          into v_payload
          from public.catalog_packages cpkg
          join public.catalog_package_variants v
            on v.package_id = cpkg.id and v.context_key = 'generell'
         where cpkg.id = p_subject_id and cpkg.status = 'published';

    elsif p_subject_type = 'draft_prompt' then
        select jsonb_build_object(
                   'kind', 'prompt',
                   'slug', ci.slug,
                   'title', ci.title,
                   'summary', ci.summary,
                   'prompt_text', ci.content,
                   'risk_level', ci.risk_level,
                   'security_examples', '[]'::jsonb
               )
          into v_payload
          from public.content_items ci
         where ci.id = p_subject_id and ci.module = 'kommun' and ci.type = 'prompt';

    elsif p_subject_type = 'package_draft' then
        select jsonb_build_object(
                   'kind', 'package',
                   'slug', d.id::text,
                   'package_type', 'collection',
                   'title', d.title,
                   'summary', d.summary,
                   'intro_text', null,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'title', ci.title,
                                  'summary', ci.summary,
                                  'prompt_text', ci.content
                              ) order by dpi.position)
                         from public.creator_package_items dpi
                         join public.content_items ci on ci.id = dpi.content_item_id
                        where dpi.draft_id = d.id
                   ), '[]'::jsonb)
               )
          into v_payload
          from public.creator_package_drafts d
         where d.id = p_subject_id;
    end if;

    return v_payload;
end;
$$;

-- 2. create_creator_share: ägarskapskontroll för alla fyra typer ----------

create or replace function app_private.create_creator_share(
    p_subject_type text,
    p_subject_id uuid,
    p_pin_version boolean default false,
    p_expires_at timestamptz default null,
    p_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := (select auth.uid());
    v_profile_id uuid;
    v_owns boolean;
    v_payload jsonb;
    v_snapshot_id uuid;
    v_token text := encode(gen_random_bytes(16), 'hex');
    v_share_id uuid;
begin
    if v_user is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    if p_subject_type not in ('prompt', 'package', 'draft_prompt', 'package_draft') then
        raise exception 'Okänd typ: %.', p_subject_type;
    end if;

    select id into v_profile_id from public.creator_profiles where user_id = v_user;
    if v_profile_id is null then
        raise exception 'Du behöver en creator-profil för att kunna dela innehåll.';
    end if;

    if p_subject_type = 'prompt' then
        select exists (
            select 1 from public.catalog_prompts
             where id = p_subject_id and status = 'published' and creator_profile_id = v_profile_id
        ) into v_owns;
    elsif p_subject_type = 'package' then
        select exists (
            select 1 from public.catalog_packages
             where id = p_subject_id and status = 'published' and creator_profile_id = v_profile_id
        ) into v_owns;
    elsif p_subject_type = 'draft_prompt' then
        select exists (
            select 1 from public.content_items
             where id = p_subject_id and owner_user_id = v_user and module = 'kommun' and type = 'prompt'
        ) into v_owns;
    else -- package_draft
        select exists (
            select 1 from public.creator_package_drafts
             where id = p_subject_id and owner_user_id = v_user
        ) into v_owns;
    end if;

    if not v_owns then
        raise exception 'Du kan bara dela ditt eget innehåll.';
    end if;

    if coalesce(p_pin_version, false) then
        v_payload := app_private.build_content_payload(p_subject_type, p_subject_id);
        if v_payload is null then
            raise exception 'Innehållet kunde inte läsas för låsning.';
        end if;
        insert into public.content_snapshots (subject_type, subject_id, payload)
        values (p_subject_type, p_subject_id, v_payload)
        returning id into v_snapshot_id;
    end if;

    insert into public.creator_shares (
        owner_user_id, subject_type, subject_id, token, snapshot_id, label, expires_at
    )
    values (
        v_user, p_subject_type, p_subject_id, v_token, v_snapshot_id,
        nullif(trim(coalesce(p_label, '')), ''), p_expires_at
    )
    returning id into v_share_id;

    return jsonb_build_object('id', v_share_id, 'token', v_token, 'pinned', v_snapshot_id is not null);
end;
$$;

-- 3. get_shared_content: nytt reviewed-fält --------------------------------

create or replace function public.get_shared_content(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_share public.creator_shares;
    v_payload jsonb;
    v_creator jsonb;
begin
    select * into v_share from public.creator_shares where token = p_token;

    if v_share.id is null then
        return jsonb_build_object('state', 'not_found');
    end if;

    if v_share.revoked_at is not null
       or (v_share.expires_at is not null and v_share.expires_at <= now()) then
        return jsonb_build_object('state', 'expired');
    end if;

    if v_share.snapshot_id is not null then
        select s.payload into v_payload
          from public.content_snapshots s where s.id = v_share.snapshot_id;
    else
        v_payload := app_private.build_content_payload(v_share.subject_type, v_share.subject_id);
    end if;

    if v_payload is null then
        return jsonb_build_object('state', 'expired');
    end if;

    select jsonb_build_object('display_name', prof.display_name, 'slug', prof.slug)
      into v_creator
      from public.creator_profiles prof
     where prof.user_id = v_share.owner_user_id
       and prof.status = 'published';

    insert into public.creator_share_events (share_id, event_type, occurred_on, event_count)
    values (v_share.id, 'view', current_date, 1)
    on conflict (share_id, event_type, occurred_on)
    do update set event_count = public.creator_share_events.event_count + 1;

    return jsonb_build_object(
        'state', 'ok',
        'pinned', v_share.snapshot_id is not null,
        'reviewed', v_share.subject_type in ('prompt', 'package'),
        'expires_at', v_share.expires_at,
        'creator', v_creator,
        'content', v_payload
    );
end;
$$;

-- 4. list_my_shareable_content ----------------------------------------------

create or replace function public.list_my_shareable_content()
returns table (
    kind text,
    subject_id uuid,
    title text,
    status_label text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user uuid := (select auth.uid());
    v_profile_id uuid;
begin
    if v_user is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    select id into v_profile_id from public.creator_profiles where user_id = v_user;

    return query
    select 'prompt'::text, cp.id, v.title, 'Publicerad'::text
      from public.catalog_prompts cp
      join public.catalog_prompt_variants v
        on v.prompt_id = cp.id and v.context_key = 'generell'
     where cp.status = 'published' and cp.creator_profile_id = v_profile_id

    union all

    select 'package'::text, cpkg.id, v.title, 'Publicerad'::text
      from public.catalog_packages cpkg
      join public.catalog_package_variants v
        on v.package_id = cpkg.id and v.context_key = 'generell'
     where cpkg.status = 'published' and cpkg.creator_profile_id = v_profile_id

    union all

    select 'draft_prompt'::text, ci.id, ci.title,
           case ci.status when 'review' then 'Under granskning' else 'Utkast' end
      from public.content_items ci
     where ci.owner_user_id = v_user
       and ci.type = 'prompt'
       and ci.module = 'kommun'
       and ci.status in ('draft', 'review')

    union all

    select 'package_draft'::text, d.id, d.title,
           case d.status when 'review' then 'Under granskning' else 'Utkast' end
      from public.creator_package_drafts d
     where d.owner_user_id = v_user
       and d.status in ('draft', 'review');
end;
$$;

revoke all on function public.list_my_shareable_content() from public;
grant execute on function public.list_my_shareable_content() to authenticated;
```

- [ ] **Step 2: Applicera migrationen mot staging/länkad produktion**

Samma metod som Task 1 Step 2.

- [ ] **Step 3: Skriv verifieringsrunbooken**

```sql
-- supabase/tests/verify_creator_shares_private_content.sql
-- Manuellt körbart end-to-end-flöde mot staging/länkad produktion.
-- Fixturer: en publicerad creator-profil, minst en egen content_items-rad
-- med module='kommun', type='prompt', status='draft' (byt in dess id
-- nedan), och minst en creator_package_drafts-rad med status='review'.

-- 1. Lista delbart innehåll.
select * from public.list_my_shareable_content();
-- Förväntat: minst en rad med kind='draft_prompt', status_label='Utkast',
-- och en rad med kind='package_draft', status_label='Under granskning'.

-- 2. Dela ett utkast, följ senaste (ej låst).
select * from public.create_creator_share('draft_prompt', '<content-item-draft-id>');
-- Förväntat: {id, token, pinned: false}.

-- 3. Läs den delade länken anonymt (byt roll till anon/ingen session).
select * from public.get_shared_content('<token-från-steg-2>');
-- Förväntat: state='ok', reviewed=false, content.prompt_text matchar
-- content_items.content för källraden.

-- 4. Redigera källraden (content_items.content) som ägaren, läs delningen
-- igen.
select * from public.get_shared_content('<token-från-steg-2>');
-- Förväntat: content.prompt_text visar det NYA innehållet -- "följ
-- senaste" läser live, ingen cache.

-- 5. Försök dela en annan användares utkast -> ska vägras.
-- Kör som EN ANNAN inloggad användare än steg 2.
select * from public.create_creator_share('draft_prompt', '<content-item-draft-id>');
-- Förväntat: ERROR 'Du kan bara dela ditt eget innehåll.'

-- 6. Publicerat innehåll ska fortfarande fungera oförändrat.
select * from public.create_creator_share('prompt', '<published-catalog-prompt-id-som-ägs-av-mig>');
select * from public.get_shared_content('<token-från-steg-6>');
-- Förväntat: som innan denna migration, reviewed=true.
```

- [ ] **Step 4: Kör runbooken mot staging och bekräfta varje förväntat resultat**

- [ ] **Step 5: Uppdatera `src/creatorShares.js`s källista**

I `promptbanken/src/creatorShares.js:33-68`, byt `loadSubjects`:

```js
// Rullistan visar allt eget delbart innehåll -- publicerat OCH eget
// opublicerat. list_my_shareable_content returnerar rätt subject_id för
// respektive kind (katalog-id för publicerat, content_items/draft-id för
// opublicerat).
async function loadSubjects() {
    const select = el('[data-share-subject]');
    const { data, error } = await supabase.rpc('list_my_shareable_content');

    select.innerHTML = '';
    if (error || !data || !data.length) {
        const option = document.createElement('option');
        option.textContent = 'Du har inget att dela än';
        option.value = '';
        select.appendChild(option);
        return;
    }

    data.forEach((item) => {
        const option = document.createElement('option');
        option.value = `${item.kind}:${item.subject_id}`;
        const kindLabel = item.kind.startsWith('package') ? 'Paket' : 'Prompt';
        option.textContent = `${kindLabel} (${item.status_label}): ${item.title}`;
        option.dataset.kind = item.kind;
        option.dataset.subjectId = item.subject_id;
        select.appendChild(option);
    });
}
```

Och i `registerCreateForm` (samma fil, rad ~187-242), ta bort
slug-uppslagningen mot katalogen (`get_published_prompt`/
`get_published_package`) eftersom `subject_id` nu kommer direkt från
`list_my_shareable_content` — den befintliga uppslagningen antog fel att
allt delbart har en katalog-slug:

```js
el('[data-share-create-btn]').addEventListener('click', async () => {
    const errorEl = el('[data-share-create-error]');
    errorEl.hidden = true;

    const select = el('[data-share-subject]');
    const option = select.selectedOptions[0];
    if (!option || !option.value) {
        errorEl.textContent = 'Välj något att dela först.';
        errorEl.hidden = false;
        return;
    }

    const { kind, subjectId } = option.dataset;

    const pinned = el('[data-share-version]:checked')?.value === 'pinned'
        || document.querySelector('[data-share-version][value="pinned"]')?.checked;

    const { data, error } = await supabase.rpc('create_creator_share', {
        p_subject_type: kind,
        p_subject_id: subjectId,
        p_pin_version: Boolean(pinned),
        p_expires_at: expiryValue(),
        p_label: el('[data-share-label]').value
    });

    if (error) {
        errorEl.textContent = error.message;
        errorEl.hidden = false;
        return;
    }

    const url = SHARE_BASE + data.token;
    el('[data-share-created-url]').textContent = url;
    el('[data-share-created]').hidden = false;
    const copyBtn = el('[data-share-created-copy]');
    copyBtn.onclick = () => copyToClipboard(url, copyBtn);

    el('[data-share-label]').value = '';
    await loadShares();
});
```

- [ ] **Step 6: Visa "inte granskat"-varning i `renderRow`**

I `src/creatorShares.js`s `renderRow` (rad ~81-150), lägg till en varning
när posten inte är publicerad. Efter raden `el('[data-row-meta]', node).textContent = meta.join(' · ');`:

```js
if (share.subject_type === 'draft_prompt' || share.subject_type === 'package_draft') {
    const warning = document.createElement('p');
    warning.className = 'mp-hint';
    warning.textContent = 'Detta innehåll är inte granskat av Promptbanken än.';
    node.querySelector('.share-row-main').appendChild(warning);
}
```

(`share.subject_type` finns redan i raden `list_my_creator_shares()`
returnerar — ingen ändring behövs där.)

- [ ] **Step 7: Lägg till bannern på den publika delningssidan**

I `promptbanken/delning/index.html`, lägg till bannerelementet direkt
efter `<article class="share-article" data-share-content hidden>`-taggen
(före `<p class="share-byline" ...>`):

```html
<p class="share-unreviewed-banner" data-share-unreviewed hidden>
    Det här innehållet är delat direkt av upphovspersonen och har inte
    granskats av Promptbanken.
</p>
```

I `promptbanken/src/share.js`, i `init()`, direkt efter raden
`const content = data.content || {};` lägg till:

```js
el('[data-share-unreviewed]').hidden = data.reviewed !== false;
```

- [ ] **Step 8: Manuell webbläsarverifiering**

1. Som en creator med minst en prompt i `draft`: öppna
   `creator-shares.html`, bekräfta att rullistan visar "Prompt (Utkast):
   ...".
2. Skapa en delning av den. Öppna länken i en privat/inkognitoflik.
   Bekräfta att "inte granskat"-bannern visas.
3. Redigera prompten i `creator-content.html`, ladda om delningslänken.
   Bekräfta att den nya texten visas (live, inte cachad) om delningen inte
   är låst.
4. Skapa en delning av en redan publicerad egen prompt. Bekräfta att
   bannern INTE visas på den länken.
5. Bekräfta att `promptbanken-mcp-contract-test`-skillens kontrollpunkter
   (9 publika verktyg) fortfarande går igenom mot produktion — denna task
   rör inte `mcp_promptbanken` eller de fem katalog-läs-RPC:erna, men kör
   ändå kontraktstestet som en sista bekräftelse innan merge.

- [ ] **Step 9: Commit**

```bash
git add supabase/migrations/20260831110000_creator_shares_private_content.sql supabase/tests/verify_creator_shares_private_content.sql src/creatorShares.js src/share.js delning/index.html
git commit -m "feat(creator): allow sharing unpublished own content"
```

---

## Self-Review

**Spec coverage:**
- Sektion F (referens kontra kopia) → Task 1 + Task 2 Step 1-4.
- Sektion G (skapa egen version) → Task 2 Step 3 (`forkReference`), redan
  befintlig RPC, ingen ny kod krävdes utöver UI-kopplingen.
- Sektion H (privat delning) → Task 4.
- Sektion L punkt 2 ("Lägg till i mitt bibliotek"-knapp i huvudkatalogen) →
  Task 3.
- Sektion L punkt 3 (generalisera creator_shares) → Task 4.
- Sektion L punkt 4 (länka `creator-shares.html`) → redan gjort i
  produktion (bekräftat i kod 2026-08-30, `creator.html:21` m.fl.), inget
  arbete kvar. Utelämnat som egen task av det skälet.
- Sektion K (Open MCP-säkerhet) → inget i denna plan rör `mcp_promptbanken`,
  `/mcp`-koden, eller de fem katalog-läs-RPC:ernas signaturer. De enda
  RPC:er som ändras (`create_creator_share`, `build_content_payload`,
  `get_shared_content`, `track_library_usage_event`) anropas aldrig av
  `mcp_promptbanken` (bekräftat i arkitekturanalysen, sektion K).

**Placeholder-scan:** Ingen "TBD"/"fyll i senare" kvar. Alla steg har
komplett, klistrbar kod.

**Typkonsekvens:** `add_catalog_prompt_to_library(p_prompt_id uuid)` heter
och tar samma parameter i migrationen (Task 1), Valvet (Task 2) och
katalogsidan (Task 3). `get_referenced_library_prompt(p_content_item_id
uuid, p_context_keys text[])` matchar mellan Task 1 och Task 2.
`list_my_shareable_content()`s kolumner (`kind`, `subject_id`, `title`,
`status_label`) matchar mellan migrationen och `creatorShares.js` i Task 4.
`window.addPublishedPromptToLibrary(promptId, button)`s signatur matchar
mellan definitionen (Task 3 Step 2) och båda anropsställena (Step 4, Step 5).
