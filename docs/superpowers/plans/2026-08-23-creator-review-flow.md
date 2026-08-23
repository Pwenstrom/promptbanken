# Redaktionellt granskningsflöde för creator-innehåll — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ge plattformsägaren en granskningsyta där creator-inskickade prompts och paket förgranskas av en AI som saknar publiceringsrättighet, godkänns manuellt in i webbkatalogen med attribution, och hålls utanför Open/MCP tills samtycke och rättigheter är på plats.

**Architecture:** Fyra lager, byggda nerifrån. (1) Migrationer som lägger till samtyckesfält, granskningstabell och katalogattribution. (2) `security definer`-RPC:er för admins läsning och beslut, alla gatade på `app_private.current_user_is_platform_owner()`. (3) En Supabase Edge Function som anropar Claude och som medvetet saknar skrivrättighet till allt utom granskningstabellen. (4) Frontend: ny adminsektion, återkoppling i creator-vyn, och attribution på de statiska sidorna.

**Tech Stack:** Supabase Postgres (RLS + `security definer`-RPC), Supabase Edge Functions (Deno), Anthropic Messages API (`claude-sonnet-5`), vanilla JS-moduler (`src/*.js`), Vite multi-page build, Node-genererade statiska sidor (`scripts/*.mjs`).

**Spec:** `docs/superpowers/specs/2026-08-23-creator-review-flow-design.md`

## Global Constraints

- Alla nya RPC:er följer repots mönster: `app_private`-implementation + `public`-wrapper, `revoke all ... from public`, `grant execute ... to authenticated`, `set search_path = ''`, svenska felmeddelanden.
- Behörighetskoll i varje admin-RPC: `if not app_private.current_user_is_platform_owner() then raise exception '...' end if;`
- Edge-funktionen får **aldrig** skrivrättighet till `content_items`, `creator_package_drafts` eller `catalog_*`. Enda skrivmålet är `creator_submission_screenings`.
- Ingen RPC och ingen funktion i denna plan sätter `catalog_prompts.status` eller `catalog_packages.status` till `'published'`. Godkännande skapar utkast; publicering sker med befintliga `publish_catalog_prompt` / `publish_catalog_package`.
- Gate-predikatet i denna leverans är `p_include_creator_content or <tabell>.creator_profile_id is null`. Det flippas inte till att släppa igenom creator-innehåll i denna plan.
- Creator-prompts identifieras som i delprojekt 3: `content_items` med `type = 'prompt'` och `module = 'kommun'`.
- Migrationsfiler namnges `supabase/migrations/YYYYMMDDHHMMSS_<namn>.sql` med fjortonsiffrigt prefix.
- `ANTHROPIC_API_KEY` sätts som Supabase-secret och får aldrig checkas in eller nå en frontend-bundle.

---

### Task 1: Migration — samtyckesfält, granskningstabell, katalogattribution

**Files:**
- Create: `supabase/migrations/20260823090000_creator_review_schema.sql`
- Create: `supabase/tests/creator_review_schema.sql`

**Interfaces:**
- Produces (konsumeras av Task 2–7):
  - `public.content_items.creator_consent_distribution boolean not null default false`
  - `public.content_items.creator_rights_attested boolean not null default false`
  - `public.creator_package_drafts.creator_consent_distribution boolean not null default false`
  - `public.creator_package_drafts.creator_rights_attested boolean not null default false`
  - `public.creator_package_drafts.review_note text`
  - `public.creator_submission_screenings(id, subject_type, subject_id, verdict, findings, suggested_feedback, rules_version, model, created_by, created_at)`
  - `public.catalog_prompts.creator_profile_id uuid`, `.creator_consent_distribution boolean`, `.creator_rights_attested boolean`
  - `public.catalog_packages.creator_profile_id uuid`, `.creator_consent_distribution boolean`, `.creator_rights_attested boolean`

- [ ] **Step 1: Läs mönsterfilen**

Läs `supabase/migrations/20260819090000_creator_authoring.sql` — den visar kommentarstilen, RLS-mönstret och hur delprojekt 3 lade till kolumner på `content_items`. Den nya migrationen ska se ut som en fortsättning på den, inte som en främmande fil.

- [ ] **Step 2: Skriv kolumnerna på källtabellerna**

```sql
-- supabase/migrations/20260823090000_creator_review_schema.sql
-- Delprojekt 4: redaktionellt granskningsflöde för creator-innehåll.
-- Se docs/superpowers/specs/2026-08-23-creator-review-flow-design.md.
--
-- Denna migration lägger bara till schema. Alla RPC:er ligger i
-- 20260823091000_creator_review_rpcs.sql och gaten i
-- 20260823092000_catalog_read_creator_gate.sql.

alter table public.content_items
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;

comment on column public.content_items.creator_consent_distribution is
    'Sant om creatorn godkänt att innehållet distribueras via Promptbanken Open/MCP till externa AI-klienter. Skilt från creator_consent_shared, som bara gäller publicering i öppna Promptbanken.';

comment on column public.content_items.creator_rights_attested is
    'Sant om creatorn intygat att innehållet är eget eller att hen har rätt att sprida det.';

alter table public.creator_package_drafts
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false,
    add column if not exists review_note text;

comment on column public.creator_package_drafts.review_note is
    'Redaktionell återkoppling när ett utkast skickats tillbaka eller avslagits. Visas för creatorn i creator-packages.html.';
```

- [ ] **Step 3: Skriv granskningstabellen**

```sql
create table if not exists public.creator_submission_screenings (
    id uuid primary key default gen_random_uuid(),
    subject_type text not null check (subject_type in ('prompt', 'package')),
    subject_id uuid not null,
    verdict text not null check (verdict in ('gron', 'gul', 'rod')),
    findings jsonb not null default '[]'::jsonb,
    suggested_feedback text,
    rules_version text not null,
    model text not null,
    created_by uuid not null references auth.users(id),
    created_at timestamptz not null default now()
);

comment on table public.creator_submission_screenings is
    'Append-only logg av AI-förgranskningar. subject_id pekar på content_items eller creator_package_drafts beroende på subject_type; medvetet utan foreign key så historiken överlever att ett utkast raderas.';

create index if not exists creator_submission_screenings_subject_idx
    on public.creator_submission_screenings (subject_type, subject_id, created_at desc);

alter table public.creator_submission_screenings enable row level security;

-- Ingen policy för anon/authenticated: åtkomst sker bara via
-- platform_owner-gatade RPC:er och via edge-funktionens service-role.
```

- [ ] **Step 4: Skriv katalogattributionen**

```sql
alter table public.catalog_prompts
    add column if not exists creator_profile_id uuid references public.creator_profiles(id) on delete set null,
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;

alter table public.catalog_packages
    add column if not exists creator_profile_id uuid references public.creator_profiles(id) on delete set null,
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;

comment on column public.catalog_prompts.creator_profile_id is
    'Satt när katalogposten kommer från ett godkänt creator-inskick. Null för kurerat redaktionellt innehåll. Distributionsgaten i list_published_* utesluter poster där denna är satt.';

create index if not exists catalog_prompts_creator_profile_idx
    on public.catalog_prompts (creator_profile_id) where creator_profile_id is not null;

create index if not exists catalog_packages_creator_profile_idx
    on public.catalog_packages (creator_profile_id) where creator_profile_id is not null;
```

- [ ] **Step 5: Skriv schematestet**

```sql
-- supabase/tests/creator_review_schema.sql
-- Kör mot staging eller länkad produktion efter migrationen.

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'content_items'
          and column_name = 'creator_consent_distribution'
    ) then
        raise exception 'FEL: content_items.creator_consent_distribution saknas';
    end if;

    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'creator_package_drafts'
          and column_name = 'review_note'
    ) then
        raise exception 'FEL: creator_package_drafts.review_note saknas';
    end if;

    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'catalog_prompts'
          and column_name = 'creator_profile_id'
    ) then
        raise exception 'FEL: catalog_prompts.creator_profile_id saknas';
    end if;

    if not exists (
        select 1 from pg_tables
        where schemaname = 'public' and tablename = 'creator_submission_screenings'
    ) then
        raise exception 'FEL: creator_submission_screenings saknas';
    end if;

    if not exists (
        select 1 from pg_tables
        where schemaname = 'public' and tablename = 'creator_submission_screenings'
          and rowsecurity = true
    ) then
        raise exception 'FEL: RLS är inte påslaget på creator_submission_screenings';
    end if;

    raise notice 'OK: schemat för granskningsflödet är på plats';
end;
$$;
```

- [ ] **Step 6: Kör migrationen mot databasen**

Använd Supabase-MCP:ns `apply_migration` med filens innehåll, eller kör filen i SQL-editorn. Kör därefter `supabase/tests/creator_review_schema.sql`.
Förväntat: `NOTICE: OK: schemat för granskningsflödet är på plats`, inga exceptions.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260823090000_creator_review_schema.sql supabase/tests/creator_review_schema.sql
git commit -m "feat(creator): add review schema, consent fields and catalog attribution"
```

---

### Task 2: RPC:er — admins läsning av inskick

**Files:**
- Create: `supabase/migrations/20260823091000_creator_review_read_rpcs.sql`
- Create: `supabase/tests/creator_review_read.sql`

**Interfaces:**
- Consumes: kolumnerna från Task 1.
- Produces:
  - `public.list_creator_submissions() returns table(subject_type text, subject_id uuid, title text, summary text, creator_profile_id uuid, creator_display_name text, creator_slug text, consent_shared boolean, consent_distribution boolean, rights_attested boolean, item_count integer, latest_verdict text, latest_screened_at timestamptz, updated_at timestamptz)`
  - `public.get_creator_submission(p_subject_type text, p_subject_id uuid) returns jsonb`

- [ ] **Step 1: Skriv listnings-RPC:n**

```sql
-- supabase/migrations/20260823091000_creator_review_read_rpcs.sql
-- Admins läsning av creator-inskick, över arbetsytegränsen.
-- Se docs/superpowers/specs/2026-08-23-creator-review-flow-design.md.

create or replace function app_private.list_creator_submissions()
returns table (
    subject_type text,
    subject_id uuid,
    title text,
    summary text,
    creator_profile_id uuid,
    creator_display_name text,
    creator_slug text,
    consent_shared boolean,
    consent_distribution boolean,
    rights_attested boolean,
    item_count integer,
    latest_verdict text,
    latest_screened_at timestamptz,
    updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa creator-inskick.';
    end if;

    return query
    select 'prompt'::text,
           ci.id,
           ci.title,
           ci.summary,
           cp.id,
           cp.display_name,
           cp.slug,
           ci.creator_consent_shared,
           ci.creator_consent_distribution,
           ci.creator_rights_attested,
           null::integer,
           s.verdict,
           s.created_at,
           ci.updated_at
      from public.content_items ci
      left join public.creator_profiles cp on cp.user_id = ci.owner_user_id
      left join lateral (
          select scr.verdict, scr.created_at
            from public.creator_submission_screenings scr
           where scr.subject_type = 'prompt' and scr.subject_id = ci.id
           order by scr.created_at desc
           limit 1
      ) s on true
     where ci.status = 'review'
       and ci.type = 'prompt'
       and ci.module = 'kommun'
       and ci.creator_consent_shared = true

    union all

    select 'package'::text,
           d.id,
           d.title,
           d.summary,
           cp.id,
           cp.display_name,
           cp.slug,
           true,
           d.creator_consent_distribution,
           d.creator_rights_attested,
           (select count(*)::integer from public.creator_package_items i where i.draft_id = d.id),
           s.verdict,
           s.created_at,
           d.updated_at
      from public.creator_package_drafts d
      left join public.creator_profiles cp on cp.user_id = d.owner_user_id
      left join lateral (
          select scr.verdict, scr.created_at
            from public.creator_submission_screenings scr
           where scr.subject_type = 'package' and scr.subject_id = d.id
           order by scr.created_at desc
           limit 1
      ) s on true
     where d.status = 'review'

     order by 13 desc nulls last;
end;
$$;

create or replace function public.list_creator_submissions()
returns table (
    subject_type text,
    subject_id uuid,
    title text,
    summary text,
    creator_profile_id uuid,
    creator_display_name text,
    creator_slug text,
    consent_shared boolean,
    consent_distribution boolean,
    rights_attested boolean,
    item_count integer,
    latest_verdict text,
    latest_screened_at timestamptz,
    updated_at timestamptz
)
language sql
security invoker
set search_path = ''
as $$
    select * from app_private.list_creator_submissions();
$$;

revoke all on function public.list_creator_submissions() from public;
grant execute on function public.list_creator_submissions() to authenticated;
```

- [ ] **Step 2: Skriv detalj-RPC:n**

```sql
create or replace function app_private.get_creator_submission(
    p_subject_type text,
    p_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_result jsonb;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan läsa creator-inskick.';
    end if;

    if p_subject_type = 'prompt' then
        select jsonb_build_object(
                   'subject_type', 'prompt',
                   'subject_id', ci.id,
                   'title', ci.title,
                   'summary', ci.summary,
                   'content', ci.content,
                   'category', ci.category,
                   'consent_shared', ci.creator_consent_shared,
                   'consent_reusable', ci.creator_consent_reusable,
                   'consent_distribution', ci.creator_consent_distribution,
                   'rights_attested', ci.creator_rights_attested,
                   'creator_display_name', cp.display_name,
                   'creator_slug', cp.slug,
                   'items', '[]'::jsonb
               )
          into v_result
          from public.content_items ci
          left join public.creator_profiles cp on cp.user_id = ci.owner_user_id
         where ci.id = p_subject_id
           and ci.status = 'review';
    elsif p_subject_type = 'package' then
        select jsonb_build_object(
                   'subject_type', 'package',
                   'subject_id', d.id,
                   'title', d.title,
                   'summary', d.summary,
                   'content', null,
                   'category', null,
                   'consent_shared', true,
                   'consent_reusable', null,
                   'consent_distribution', d.creator_consent_distribution,
                   'rights_attested', d.creator_rights_attested,
                   'creator_display_name', cp.display_name,
                   'creator_slug', cp.slug,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'content_item_id', ci.id,
                                  'title', ci.title,
                                  'content', ci.content,
                                  'status', ci.status::text,
                                  'position', i.position
                              ) order by i.position)
                         from public.creator_package_items i
                         join public.content_items ci on ci.id = i.content_item_id
                        where i.draft_id = d.id
                   ), '[]'::jsonb)
               )
          into v_result
          from public.creator_package_drafts d
          left join public.creator_profiles cp on cp.user_id = d.owner_user_id
         where d.id = p_subject_id
           and d.status = 'review';
    else
        raise exception 'Okänd typ: %. Ange prompt eller package.', p_subject_type;
    end if;

    if v_result is null then
        raise exception 'Inskicket hittades inte eller är inte under granskning.';
    end if;

    return v_result || jsonb_build_object('screenings', coalesce((
        select jsonb_agg(jsonb_build_object(
                   'verdict', scr.verdict,
                   'findings', scr.findings,
                   'suggested_feedback', scr.suggested_feedback,
                   'rules_version', scr.rules_version,
                   'model', scr.model,
                   'created_at', scr.created_at
               ) order by scr.created_at desc)
          from public.creator_submission_screenings scr
         where scr.subject_type = p_subject_type
           and scr.subject_id = p_subject_id
    ), '[]'::jsonb));
end;
$$;

create or replace function public.get_creator_submission(p_subject_type text, p_subject_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.get_creator_submission(p_subject_type, p_subject_id);
$$;

revoke all on function public.get_creator_submission(text, uuid) from public;
grant execute on function public.get_creator_submission(text, uuid) to authenticated;
```

- [ ] **Step 3: Skriv behörighetstestet**

```sql
-- supabase/tests/creator_review_read.sql
-- Kör som en INTE-plattformsägare (t.ex. via en vanlig användares JWT i
-- SQL-editorns "run as" eller via PostgREST med den användarens token).

do $$
declare
    v_failed boolean := false;
begin
    begin
        perform * from public.list_creator_submissions();
        v_failed := true;
    exception when others then
        raise notice 'OK: list_creator_submissions avvisade icke-plattformsägare';
    end;

    if v_failed then
        raise exception 'FEL: list_creator_submissions släppte igenom en icke-plattformsägare';
    end if;

    begin
        perform public.get_creator_submission('prompt', gen_random_uuid());
        v_failed := true;
    exception when others then
        raise notice 'OK: get_creator_submission avvisade icke-plattformsägare';
    end;

    if v_failed then
        raise exception 'FEL: get_creator_submission släppte igenom en icke-plattformsägare';
    end if;
end;
$$;
```

- [ ] **Step 4: Kör migrationen och testet**

Kör migrationen. Kör sedan `supabase/tests/creator_review_read.sql` som en vanlig användare.
Förväntat: två `OK:`-notiser, inget exception.

Kör därefter som plattformsägare:
```sql
select * from public.list_creator_submissions();
```
Förväntat: tom tabell eller befintliga inskick, inget fel. (Produktionen hade 0 poster i `review` och 1 paket-utkast 2026-08-23.)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260823091000_creator_review_read_rpcs.sql supabase/tests/creator_review_read.sql
git commit -m "feat(creator): add platform-owner RPCs for reading creator submissions"
```

---

### Task 3: RPC:er — besluten (godkänn, begär ändring, avslå)

**Files:**
- Create: `supabase/migrations/20260823093000_creator_review_decision_rpcs.sql`
- Create: `supabase/tests/creator_review_decisions.sql`

**Interfaces:**
- Consumes: Task 1:s kolumner, `app_private.current_user_is_platform_owner()`, befintliga `catalog_prompts`/`catalog_prompt_variants`/`catalog_packages`/`catalog_package_variants`/`catalog_package_items`.
- Produces:
  - `public.approve_creator_prompt(p_content_item_id uuid, p_slug text, p_icon_key text, p_color_theme text) returns jsonb`
  - `public.approve_creator_package(p_draft_id uuid, p_slug text, p_icon_key text, p_color_theme text) returns jsonb`
  - `public.request_changes_creator_submission(p_subject_type text, p_subject_id uuid, p_note text) returns jsonb`
  - `public.reject_creator_submission(p_subject_type text, p_subject_id uuid, p_note text) returns jsonb`

- [ ] **Step 1: Läs de befintliga katalogskrivarna**

Läs `supabase/migrations/20260721110000_catalog_prompt_rpcs.sql` och `20260721120000_catalog_package_rpcs.sql`. Godkännandet skriver till samma tabeller och måste fylla samma obligatoriska variantfält (`title`, `summary`, `prompt_text` för prompts; `title`, `summary` för paket). Kontrollera vilka kolumner som är `not null` innan du skriver insert-satserna.

- [ ] **Step 2: Skriv godkännandet för prompts**

```sql
-- supabase/migrations/20260823093000_creator_review_decision_rpcs.sql
-- Redaktionella beslut. AI:n har ingen del i dessa funktioner: de kräver
-- en inloggad plattformsägare och läser aldrig granskningsresultatet.

create or replace function app_private.approve_creator_prompt(
    p_content_item_id uuid,
    p_slug text,
    p_icon_key text,
    p_color_theme text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_item public.content_items;
    v_creator_profile_id uuid;
    v_prompt_id uuid;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan godkänna creator-inskick.';
    end if;

    select * into v_item
      from public.content_items
     where id = p_content_item_id and status = 'review';

    if v_item.id is null then
        raise exception 'Prompten hittades inte eller är inte under granskning.';
    end if;

    if not v_item.creator_consent_shared then
        raise exception 'Prompten saknar creatorns samtycke till publicering och kan inte godkännas.';
    end if;

    if exists (select 1 from public.catalog_prompts where slug = p_slug) then
        raise exception 'Adressen % är redan tagen i katalogen. Ange en annan.', p_slug;
    end if;

    select id into v_creator_profile_id
      from public.creator_profiles
     where user_id = v_item.owner_user_id;

    insert into public.catalog_prompts (
        slug, status, prompt_kind, icon_key, color_theme,
        creator_profile_id, creator_consent_distribution, creator_rights_attested,
        created_by, updated_by
    )
    values (
        p_slug, 'draft', 'prompt', p_icon_key, p_color_theme,
        v_creator_profile_id, v_item.creator_consent_distribution, v_item.creator_rights_attested,
        (select auth.uid()), (select auth.uid())
    )
    returning id into v_prompt_id;

    insert into public.catalog_prompt_variants (
        prompt_id, context_key, title, summary, prompt_text
    )
    values (
        v_prompt_id, 'generell', v_item.title,
        coalesce(v_item.summary, v_item.title), v_item.content
    );

    update public.content_items
       set status = 'published',
           review_note = null,
           updated_at = now()
     where id = p_content_item_id;

    return jsonb_build_object(
        'catalog_prompt_id', v_prompt_id,
        'slug', p_slug,
        'status', 'draft',
        'creator_profile_id', v_creator_profile_id
    );
end;
$$;

create or replace function public.approve_creator_prompt(
    p_content_item_id uuid,
    p_slug text,
    p_icon_key text,
    p_color_theme text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.approve_creator_prompt(p_content_item_id, p_slug, p_icon_key, p_color_theme);
$$;

revoke all on function public.approve_creator_prompt(uuid, text, text, text) from public;
grant execute on function public.approve_creator_prompt(uuid, text, text, text) to authenticated;
```

- [ ] **Step 3: Skriv godkännandet för paket**

```sql
create or replace function app_private.approve_creator_package(
    p_draft_id uuid,
    p_slug text,
    p_icon_key text,
    p_color_theme text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_draft public.creator_package_drafts;
    v_creator_profile_id uuid;
    v_package_id uuid;
    v_missing text;
    v_item record;
    v_sort integer := 0;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan godkänna creator-inskick.';
    end if;

    select * into v_draft
      from public.creator_package_drafts
     where id = p_draft_id and status = 'review';

    if v_draft.id is null then
        raise exception 'Paket-utkastet hittades inte eller är inte under granskning.';
    end if;

    if exists (select 1 from public.catalog_packages where slug = p_slug) then
        raise exception 'Adressen % är redan tagen i katalogen. Ange en annan.', p_slug;
    end if;

    -- Varje ingående prompt måste redan ha en katalogpost. Godkänn dem
    -- först, annars går paketet inte att bygga.
    select string_agg(ci.title, ', ' order by i.position) into v_missing
      from public.creator_package_items i
      join public.content_items ci on ci.id = i.content_item_id
     where i.draft_id = p_draft_id
       and not exists (
           select 1 from public.catalog_prompt_variants v
            where v.prompt_text = ci.content and v.context_key = 'generell'
       );

    if v_missing is not null then
        raise exception 'Dessa prompts saknar godkänd katalogpost och måste godkännas först: %', v_missing;
    end if;

    select id into v_creator_profile_id
      from public.creator_profiles
     where user_id = v_draft.owner_user_id;

    insert into public.catalog_packages (
        slug, status, package_type, icon_key, color_theme,
        creator_profile_id, creator_consent_distribution, creator_rights_attested,
        created_by, updated_by
    )
    values (
        p_slug, 'draft', 'collection', p_icon_key, p_color_theme,
        v_creator_profile_id, v_draft.creator_consent_distribution, v_draft.creator_rights_attested,
        (select auth.uid()), (select auth.uid())
    )
    returning id into v_package_id;

    insert into public.catalog_package_variants (package_id, context_key, title, summary)
    values (v_package_id, 'generell', v_draft.title, coalesce(v_draft.summary, v_draft.title));

    for v_item in
        select cp.id as prompt_id
          from public.creator_package_items i
          join public.content_items ci on ci.id = i.content_item_id
          join public.catalog_prompt_variants v
            on v.prompt_text = ci.content and v.context_key = 'generell'
          join public.catalog_prompts cp on cp.id = v.prompt_id
         where i.draft_id = p_draft_id
         order by i.position
    loop
        insert into public.catalog_package_items (package_id, prompt_id, sort_order)
        values (v_package_id, v_item.prompt_id, v_sort)
        on conflict (package_id, prompt_id) do nothing;
        v_sort := v_sort + 1;
    end loop;

    update public.creator_package_drafts
       set status = 'published',
           review_note = null,
           updated_at = now()
     where id = p_draft_id;

    return jsonb_build_object(
        'catalog_package_id', v_package_id,
        'slug', p_slug,
        'status', 'draft',
        'item_count', v_sort,
        'creator_profile_id', v_creator_profile_id
    );
end;
$$;

create or replace function public.approve_creator_package(
    p_draft_id uuid,
    p_slug text,
    p_icon_key text,
    p_color_theme text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.approve_creator_package(p_draft_id, p_slug, p_icon_key, p_color_theme);
$$;

revoke all on function public.approve_creator_package(uuid, text, text, text) from public;
grant execute on function public.approve_creator_package(uuid, text, text, text) to authenticated;
```

- [ ] **Step 4: Skriv begär-ändring och avslå**

```sql
create or replace function app_private.set_creator_submission_status(
    p_subject_type text,
    p_subject_id uuid,
    p_note text,
    p_new_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if not app_private.current_user_is_platform_owner() then
        raise exception 'Endast plattformsägare kan besluta om creator-inskick.';
    end if;

    if coalesce(trim(p_note), '') = '' then
        raise exception 'Skriv en motivering till creatorn innan du skickar tillbaka eller avslår.';
    end if;

    if p_subject_type = 'prompt' then
        update public.content_items
           set status = p_new_status::public.content_status,
               review_note = p_note,
               updated_at = now()
         where id = p_subject_id and status = 'review'
        returning id into v_id;
    elsif p_subject_type = 'package' then
        update public.creator_package_drafts
           set status = p_new_status,
               review_note = p_note,
               updated_at = now()
         where id = p_subject_id and status = 'review'
        returning id into v_id;
    else
        raise exception 'Okänd typ: %. Ange prompt eller package.', p_subject_type;
    end if;

    if v_id is null then
        raise exception 'Inskicket hittades inte eller är inte under granskning.';
    end if;

    return jsonb_build_object('id', v_id, 'status', p_new_status);
end;
$$;

create or replace function public.request_changes_creator_submission(
    p_subject_type text,
    p_subject_id uuid,
    p_note text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.set_creator_submission_status(p_subject_type, p_subject_id, p_note, 'draft');
$$;

create or replace function public.reject_creator_submission(
    p_subject_type text,
    p_subject_id uuid,
    p_note text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.set_creator_submission_status(p_subject_type, p_subject_id, p_note, 'archived');
$$;

revoke all on function public.request_changes_creator_submission(text, uuid, text) from public;
grant execute on function public.request_changes_creator_submission(text, uuid, text) to authenticated;
revoke all on function public.reject_creator_submission(text, uuid, text) from public;
grant execute on function public.reject_creator_submission(text, uuid, text) to authenticated;
```

- [ ] **Step 5: Skriv beslutstestet**

```sql
-- supabase/tests/creator_review_decisions.sql
-- Kör som plattformsägare. Skapar sitt eget testdata och städar upp.

do $$
declare
    v_owner uuid := (select auth.uid());
    v_workspace uuid;
    v_item uuid;
    v_result jsonb;
    v_slug text := 'testprompt-' || substr(gen_random_uuid()::text, 1, 8);
begin
    select id into v_workspace from public.workspaces where owner_user_id = v_owner limit 1;
    if v_workspace is null then
        raise exception 'Testet kräver att den inloggade äger minst en arbetsyta.';
    end if;

    insert into public.content_items (workspace_id, owner_user_id, type, module, title, summary, content, status, visibility, creator_consent_shared, creator_consent_distribution, creator_rights_attested)
    values (v_workspace, v_owner, 'prompt', 'kommun', 'Testprompt för granskning', 'Sammanfattning', 'Skriv ett svar om X.', 'review', 'private', true, true, true)
    returning id into v_item;

    v_result := public.approve_creator_prompt(v_item, v_slug, 'library', null);

    if (v_result->>'status') <> 'draft' then
        raise exception 'FEL: katalogposten skapades inte som utkast';
    end if;

    if not exists (
        select 1 from public.catalog_prompts
         where id = (v_result->>'catalog_prompt_id')::uuid
           and creator_consent_distribution = true
           and creator_rights_attested = true
           and creator_profile_id is not distinct from (v_result->>'creator_profile_id')::uuid
    ) then
        raise exception 'FEL: distributionsflaggorna kopierades inte till katalogposten';
    end if;

    if (select status::text from public.content_items where id = v_item) <> 'published' then
        raise exception 'FEL: källposten sattes inte till published';
    end if;

    raise notice 'OK: approve_creator_prompt skapar utkast och kopierar attributionen';

    delete from public.catalog_prompts where id = (v_result->>'catalog_prompt_id')::uuid;
    delete from public.content_items where id = v_item;
end;
$$;
```

- [ ] **Step 6: Kör migrationen och testet**

Kör migrationen, sedan testfilen som plattformsägare.
Förväntat: `NOTICE: OK: approve_creator_prompt skapar utkast och kopierar attributionen`.

Kör även den negativa vägen som vanlig användare:
```sql
select public.request_changes_creator_submission('prompt', gen_random_uuid(), 'test');
```
Förväntat: `ERROR: Endast plattformsägare kan besluta om creator-inskick.`

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260823093000_creator_review_decision_rpcs.sql supabase/tests/creator_review_decisions.sql
git commit -m "feat(creator): add approve, request-changes and reject RPCs"
```

---

### Task 4: Distributionsgaten på de fem publika läs-RPC:erna

**Files:**
- Create: `supabase/migrations/20260823094000_catalog_read_creator_gate.sql`
- Create: `supabase/tests/catalog_read_creator_gate.sql`
- Modify: `script.js` (anropen till `list_published_prompts` / `get_published_prompt`)
- Modify: `promptbanken.html` (samma anrop om de ligger inline)
- Modify: `scripts/generate-catalog-pages.mjs:76,92`

**Interfaces:**
- Consumes: `catalog_prompts.creator_profile_id`, `catalog_packages.creator_profile_id` från Task 1.
- Produces: fem RPC:er med ny trailing-parameter `p_include_creator_content boolean default false`.

**Detta är planens farligaste steg.** Det ändrar signaturen på funktioner som både webben, sidgeneratorn och den hostade MCP:n i repot `mcp_promptbanken` anropar i produktion.

- [ ] **Step 1: Hämta de nuvarande definitionerna ordagrant**

De senaste definitionerna ligger i:

| Funktion | Senaste definition |
| --- | --- |
| `list_published_prompts` | `supabase/migrations/20260802100000_catalog_security_examples.sql` |
| `get_published_prompt` | `supabase/migrations/20260802100000_catalog_security_examples.sql` |
| `list_published_packages` | `supabase/migrations/20260815090000_catalog_package_seo_fields.sql` |
| `get_published_package` | `supabase/migrations/20260815090000_catalog_package_seo_fields.sql` |
| `list_published_package_prompts` | `supabase/migrations/20260725133000_catalog_parameter_schemas.sql` |

Kopiera varje funktionskropp därifrån. Varje utelämnad returkolumn är ett produktionsfel i både webben och MCP:n.

Verifiera samtidigt mot databasen att inget hunnit ändras:
```sql
select p.proname, pg_get_function_identity_arguments(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname like 'list_published%' or p.proname like 'get_published%';
```
Förväntat 2026-08-23: exakt en överlagring per funktion, med argumenten `p_context_keys text[]` respektive `p_slug text, p_context_keys text[]`.

- [ ] **Step 2: Skriv migrationen med drop före create**

En trailing default-parameter skapar en **andra** överlagring, inte en ersättning. PostgREST anropar med namngivna argument, och två matchande överlagringar ger `function is not unique`. Den gamla signaturen måste därför droppas i samma transaktion.

```sql
-- supabase/migrations/20260823094000_catalog_read_creator_gate.sql
-- Distributionsgate: creator-innehåll når inte Open/MCP.
--
-- Webben och scripts/generate-catalog-pages.mjs skickar
-- p_include_creator_content => true. Den hostade MCP:n i repot
-- mcp_promptbanken skickar ingenting och får därmed filtrerat resultat
-- utan att en rad ändras där. Defaultens riktning är poängen: en glömd
-- kodrad kan bara utesluta för mycket, aldrig läcka.
--
-- OBS: drop före create krävs. Utan droppen finns två överlagringar och
-- PostgREST-anrop med namngivna argument ger "function is not unique".

drop function if exists public.list_published_prompts(text[]);

create or replace function public.list_published_prompts(
    p_context_keys text[] default array['generell'],
    p_include_creator_content boolean default false
)
returns table (
    -- ... samtliga returkolumner ordagrant från
    -- 20260802100000_catalog_security_examples.sql ...
)
language sql
security definer
set search_path = ''
as $$
    -- ... samma kropp, med detta tillägg i where-satsen:
    --   and (p_include_creator_content or cp.creator_profile_id is null)
$$;

revoke all on function public.list_published_prompts(text[], boolean) from public;
grant execute on function public.list_published_prompts(text[], boolean) to anon, authenticated;
```

Upprepa samma mönster för de fyra övriga. För `list_published_package_prompts` filtreras på paketets `creator_profile_id`, inte prompternas — ett paket som är kurerat men innehåller en creator-prompt ska inte kunna uppstå, eftersom `approve_creator_package` alltid sätter attribution på paketet.

Behåll `grant`-mottagarna exakt som de var i respektive källmigration.

- [ ] **Step 3: Skriv gate-testet**

```sql
-- supabase/tests/catalog_read_creator_gate.sql
-- Kör som plattformsägare. Skapar en publicerad creator-katalogpost,
-- kontrollerar gaten åt båda håll, städar upp.

do $$
declare
    v_profile uuid;
    v_prompt uuid;
    v_slug text := 'gatetest-' || substr(gen_random_uuid()::text, 1, 8);
    v_default_count integer;
    v_included_count integer;
begin
    select id into v_profile from public.creator_profiles limit 1;
    if v_profile is null then
        raise exception 'Testet kräver minst en creator_profiles-rad.';
    end if;

    insert into public.catalog_prompts (slug, status, prompt_kind, creator_profile_id)
    values (v_slug, 'published', 'prompt', v_profile)
    returning id into v_prompt;

    insert into public.catalog_prompt_variants (prompt_id, context_key, title, summary, prompt_text)
    values (v_prompt, 'generell', 'Gate-test', 'Sammanfattning', 'Text');

    select count(*) into v_default_count
      from public.list_published_prompts(array['generell'])
     where slug = v_slug;

    select count(*) into v_included_count
      from public.list_published_prompts(array['generell'], true)
     where slug = v_slug;

    if v_default_count <> 0 then
        raise exception 'FEL: creator-innehåll syntes med defaultanropet (MCP-vägen)';
    end if;

    if v_included_count <> 1 then
        raise exception 'FEL: creator-innehåll syntes inte med p_include_creator_content => true (webbvägen)';
    end if;

    raise notice 'OK: gaten utesluter creator-innehåll som default och släpper igenom det för webben';

    delete from public.catalog_prompts where id = v_prompt;
end;
$$;
```

- [ ] **Step 4: Kör migrationen och testet**

Kör migrationen. Kör testfilen.
Förväntat: `NOTICE: OK: gaten utesluter creator-innehåll som default och släpper igenom det för webben`.

- [ ] **Step 5: Verifiera via den faktiska PostgREST-vägen**

SQL-editorn räcker inte — `mcp_promptbanken`-repots LOG.md dokumenterar en incident där en saknad `public`-wrapper upptäcktes först i produktion. Anropa över REST:

```bash
curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/list_published_prompts" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_context_keys":["generell"]}' | head -c 400
```
Förväntat: giltig JSON-array, **inget** `function is not unique`-fel, och inga creator-poster.

- [ ] **Step 6: Uppdatera webbens anropare**

I `scripts/generate-catalog-pages.mjs` rad 76 och 92, och i motsvarande anrop i `script.js` och `promptbanken.html`, lägg till `p_include_creator_content: true` i argumentobjektet. Exempel:

```javascript
const packages = await rpc('list_published_packages', {
    p_context_keys: contextKeys,
    p_include_creator_content: true
});
```

Sök upp samtliga anrop först:
```bash
grep -n "list_published_\|get_published_" script.js promptbanken.html scripts/generate-catalog-pages.mjs
```

- [ ] **Step 7: Verifiera att webben fortfarande visar hela katalogen**

Kör `npm run web:dev`, öppna katalogsidan och räkna korten. Förväntat: samma antal som före ändringen (102 publicerade prompts, 17 paket i produktion 2026-08-23).

Kör även sidgeneratorn:
```bash
node scripts/generate-catalog-pages.mjs
```
Förväntat: samma rad som tidigare, `17 paketsidor skrivna ...`, inget tapp.

- [ ] **Step 8: Kör MCP-kontraktstestet**

Använd skillen `promptbanken-mcp-contract-test` mot produktion. Förväntat: de nio publika verktygen svarar som före ändringen.

- [ ] **Step 9: Commit**

```bash
git add supabase/migrations/20260823094000_catalog_read_creator_gate.sql supabase/tests/catalog_read_creator_gate.sql script.js promptbanken.html scripts/generate-catalog-pages.mjs
git commit -m "feat(catalog): gate creator content out of Open/MCP by default"
```

---

### Task 5: Publiceringsreglerna och edge-funktionen

**Files:**
- Create: `docs/creator-publiceringsregler.md`
- Create: `supabase/functions/screen-creator-submission/index.ts`
- Create: `supabase/functions/screen-creator-submission/rules.ts`

**Interfaces:**
- Consumes: `public.get_creator_submission(text, uuid)` från Task 2, `creator_submission_screenings` från Task 1.
- Produces: HTTP-endpoint `POST /functions/v1/screen-creator-submission` med kroppen `{ subject_type: 'prompt'|'package', subject_id: string }`, som returnerar `{ verdict, findings, suggested_feedback, rules_version, model, created_at }`.

- [ ] **Step 1: Skriv publiceringsreglerna**

```markdown
<!-- version: 2026-08-23.1 -->
# Promptbankens publiceringsregler för creator-innehåll

Reglerna nedan används av den automatiska förgranskningen och av den
redaktionella bedömningen. De är formulerade som krav på innehållet, inte
som instruktioner till en modell.

## 1. Form och språk

- Svenska, om prompten inte uttryckligen handlar om ett annat språk.
- Prompten ska tala om vad mottagaren ska göra, inte vara en fråga i luften.
- Platshållare skrivs som `[klistra in här]` eller `[TEXT]`.
- Ingen inledande artighetsfras riktad till modellen.

## 2. Kvalitet

- Prompten ska ge ett användbart resultat utan att användaren behöver
  skriva om den.
- Den ska vara konkret nog att två olika användare får jämförbara svar.
- Sammanfattningen ska beskriva vad prompten gör, inte vem den är för.

## 3. Risk

- Prompten får inte be användaren klistra in personnummer, namn på
  enskilda, diarienummer eller andra personuppgifter.
- Prompten får inte formulera myndighetsbeslut, medicinska bedömningar
  eller juridisk rådgivning som om de vore färdiga att använda.
- Prompter som rör känsliga områden ska påminna om mänsklig granskning.

## 4. Rättigheter

- Innehållet ska vara creatorns eget eller något hen har rätt att sprida.
- Längre citat, metodbeskrivningar med känt upphov eller igenkännbart
  material från en identifierbar källa ska flaggas.
- Varumärken och organisationsnamn får inte antyda samarbete som inte finns.

## 5. Dubletter

- Innehåll som i praktiken gör samma sak som en befintlig katalogpost ska
  flaggas med vilken post det gäller.
- Att täcka samma ämne är inte en dublett. Att lösa samma uppgift på samma
  sätt är det.
```

- [ ] **Step 2: Baka in reglerna i funktionen**

Edge-funktioner kan inte läsa godtyckliga repofiler i runtime. Reglerna bakas in som en sträng:

```typescript
// supabase/functions/screen-creator-submission/rules.ts
//
// GENERERAD SPEGLING av docs/creator-publiceringsregler.md.
// Ändra markdownfilen först, kopiera hit, deploya. Versionsraden måste
// matcha, annars pekar rules_version på fel regelverk.

export const RULES_VERSION = "2026-08-23.1";

export const RULES_MARKDOWN = `# Promptbankens publiceringsregler för creator-innehåll
... hela innehållet från docs/creator-publiceringsregler.md utom versionsraden ...
`;
```

- [ ] **Step 3: Skriv edge-funktionen**

```typescript
// supabase/functions/screen-creator-submission/index.ts
//
// AI-förgranskning av creator-inskick. Rådgivande, aldrig beslutande.
//
// Säkerhetsgräns: denna funktion skriver i exakt en tabell,
// creator_submission_screenings. Den har ingen väg att ändra status på
// content_items, creator_package_drafts eller catalog_*. Det är därför en
// kapad modellprompt inte kan publicera eller avslå något.

import { createClient } from "npm:@supabase/supabase-js@2";
import { RULES_MARKDOWN, RULES_VERSION } from "./rules.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const MODEL = "claude-sonnet-5";

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const SCREENING_TOOL = {
  name: "lamna_omdome",
  description: "Lämna granskningsomdöme för ett creator-inskick.",
  input_schema: {
    type: "object",
    properties: {
      verdict: { type: "string", enum: ["gron", "gul", "rod"] },
      findings: {
        type: "array",
        items: {
          type: "object",
          properties: {
            kategori: {
              type: "string",
              enum: ["regelverk", "kvalitet", "risk", "rattigheter", "dublett"],
            },
            allvarlighet: { type: "string", enum: ["hog", "medel", "lag"] },
            text: { type: "string" },
          },
          required: ["kategori", "allvarlighet", "text"],
        },
      },
      suggested_feedback: { type: "string" },
    },
    required: ["verdict", "findings", "suggested_feedback"],
  },
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Saknar Authorization-header." }, 401);
  }

  const { subject_type, subject_id } = await req.json();
  if (subject_type !== "prompt" && subject_type !== "package") {
    return jsonResponse({ error: "Okänd typ. Ange prompt eller package." }, 400);
  }

  // Anroparens egen JWT. get_creator_submission gör platform_owner-kollen
  // åt oss - misslyckas den är anroparen inte behörig.
  const callerClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData } = await callerClient.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  const userId = userData?.user?.id;
  if (!userId) {
    return jsonResponse({ error: "Ogiltig session." }, 401);
  }

  const { data: submission, error: submissionError } = await callerClient
    .rpc("get_creator_submission", {
      p_subject_type: subject_type,
      p_subject_id: subject_id,
    });

  if (submissionError) {
    return jsonResponse({ error: submissionError.message }, 403);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: catalogPrompts } = await admin
    .from("catalog_prompt_variants")
    .select("title, summary, catalog_prompts!inner(slug, status)")
    .eq("context_key", "generell")
    .eq("catalog_prompts.status", "published");

  const comparisonList = (catalogPrompts ?? [])
    .map((row: Record<string, unknown>) => `- ${row.title}: ${row.summary}`)
    .join("\n");

  const subjectText = subject_type === "prompt"
    ? `Titel: ${submission.title}\nSammanfattning: ${submission.summary ?? ""}\n\nPrompttext:\n${submission.content}`
    : `Pakettitel: ${submission.title}\nSammanfattning: ${submission.summary ?? ""}\n\nIngående prompts i ordning:\n` +
      (submission.items as Array<Record<string, unknown>>)
        .map((item, index) => `${index + 1}. ${item.title}\n${item.content}`)
        .join("\n\n");

  const packageInstruction = subject_type === "package"
    ? "\n\nFör paket: bedöm helheten. Hänger prompterna ihop, är ordningen logisk, överlappar de varandra, motsvarar titel och sammanfattning innehållet?"
    : "";

  const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 2000,
      tools: [SCREENING_TOOL],
      tool_choice: { type: "tool", name: "lamna_omdome" },
      messages: [{
        role: "user",
        content:
          `Du granskar ett inskick till Promptbanken mot publiceringsreglerna nedan. ` +
          `Du fattar inget beslut - en människa gör det. Ge ett omdöme, korta fynd, ` +
          `och ett förslag på återkoppling skrivet direkt till creatorn på svenska.` +
          packageInstruction +
          `\n\n## Publiceringsregler\n\n${RULES_MARKDOWN}` +
          `\n\n## Befintlig katalog (för dublettbedömning)\n\n${comparisonList}` +
          `\n\n## Inskicket\n\n${subjectText}`,
      }],
    }),
  });

  if (!anthropicResponse.ok) {
    const detail = await anthropicResponse.text();
    return jsonResponse(
      { error: `Granskningen kunde inte köras: ${anthropicResponse.status} ${detail.slice(0, 200)}` },
      502,
    );
  }

  const payload = await anthropicResponse.json();
  const toolUse = payload.content?.find(
    (block: Record<string, unknown>) => block.type === "tool_use",
  );

  // Otolkbart svar: skriv ingen rad, gissa aldrig ett verdikt.
  if (!toolUse?.input?.verdict) {
    return jsonResponse(
      { error: "Modellen svarade i ett format som inte gick att tolka. Ingen granskning sparades." },
      502,
    );
  }

  const { data: inserted, error: insertError } = await admin
    .from("creator_submission_screenings")
    .insert({
      subject_type,
      subject_id,
      verdict: toolUse.input.verdict,
      findings: toolUse.input.findings ?? [],
      suggested_feedback: toolUse.input.suggested_feedback ?? null,
      rules_version: RULES_VERSION,
      model: MODEL,
      created_by: userId,
    })
    .select()
    .single();

  if (insertError) {
    return jsonResponse({ error: insertError.message }, 500);
  }

  return jsonResponse(inserted, 200);
});
```

- [ ] **Step 4: Sätt API-nyckeln som secret**

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```
Verifiera att nyckeln inte finns i repot:
```bash
git grep -n "sk-ant-" || echo "OK: ingen nyckel i repot"
```
Förväntat: `OK: ingen nyckel i repot`.

- [ ] **Step 5: Deploya och rökprova**

```bash
supabase functions deploy screen-creator-submission
```

Anropa med en riktig admin-JWT och ett riktigt inskick i `review`. Finns inget, skapa ett testinskick som i Task 3:s testfil.

Förväntat: HTTP 200 med `verdict`, `findings`, `suggested_feedback`, `rules_version: "2026-08-23.1"`.

Kör sedan samma anrop med en JWT som **inte** är plattformsägare.
Förväntat: HTTP 403 med felmeddelandet från `get_creator_submission`.

- [ ] **Step 6: Verifiera säkerhetsgränsen**

Detta är plikten, inte en formalitet. Bekräfta att funktionen inte kan ändra status någonstans:

```bash
grep -n "content_items\|creator_package_drafts\|catalog_prompts\|catalog_packages" supabase/functions/screen-creator-submission/index.ts
```
Förväntat: träffar bara på läsning (`catalog_prompt_variants`-selecten) och ingen `.update(`, `.insert(` eller `.delete(` mot dessa tabeller. Enda skrivningen i filen ska vara `.from("creator_submission_screenings").insert(`.

- [ ] **Step 7: Commit**

```bash
git add docs/creator-publiceringsregler.md supabase/functions/screen-creator-submission/
git commit -m "feat(creator): add publishing rules and advisory AI screening function"
```

---

### Task 6: Granskningsvyn i admin

**Files:**
- Create: `src/adminCreatorReview.js`
- Modify: `admin.html:22-29` (navigationslänk), `admin.html:184` (ny sektion före `</main>`), `admin.html:189` (ny script-tagg)

**Interfaces:**
- Consumes: `list_creator_submissions()`, `get_creator_submission(text, uuid)`, `approve_creator_prompt(...)`, `approve_creator_package(...)`, `request_changes_creator_submission(...)`, `reject_creator_submission(...)`, samt edge-funktionen från Task 5.
- Produces: inget som senare tasks konsumerar.

- [ ] **Step 1: Läs mönstermodulen**

Läs `src/adminCreatorProfiles.js` i sin helhet (179 rader). Den visar exakt hur en adminsektion byggs i detta repo: `requireSupabaseConfig`, sessionskoll, `data-`-attribut som väljare, nekad-vy för icke-behöriga, och ingen delad tillståndsbutik. Den nya modulen ska följa samma form.

- [ ] **Step 2: Skriv markup i admin.html**

Navigationslänk, efter raden för `#creator-profiler`:

```html
<a class="admin-nav-link" href="#creator-granskning"><span class="app-icon" data-icon="shield"></span>Creator-granskning</a>
```

Sektion, före `</main>`:

```html
<section class="workspace-section" id="creator-granskning" aria-labelledby="creator-granskning-title">
    <div class="workspace-section-head">
        <h2 id="creator-granskning-title">Creator-granskning</h2>
        <button type="button" data-review-refresh>Uppdatera</button>
    </div>
    <p class="workspace-status" role="status" data-review-status>Laddar inskick...</p>
    <section class="workspace-empty" data-review-denied hidden>
        <p>Bara plattformsägare kan granska creator-inskick.</p>
    </section>
    <div data-review-list hidden></div>

    <template data-review-row-template>
        <article class="review-card">
            <div class="review-card-head">
                <h3 data-review-title></h3>
                <span class="review-verdict" data-review-verdict></span>
            </div>
            <p class="review-meta" data-review-meta></p>
            <p class="review-consents" data-review-consents></p>
            <div class="review-detail" data-review-detail hidden></div>
            <div class="review-actions">
                <button type="button" data-review-open>Visa</button>
                <button type="button" data-review-screen>Kör granskning</button>
                <button type="button" data-review-approve>Godkänn</button>
                <button type="button" data-review-changes>Begär ändring</button>
                <button type="button" data-review-reject>Avslå</button>
            </div>
            <p class="mp-hint is-error" data-review-error hidden></p>
        </article>
    </template>
</section>
```

Script-tagg, efter `adminCreatorProfiles.js`:

```html
<script type="module" src="/src/adminCreatorReview.js"></script>
```

- [ ] **Step 3: Skriv modulens laddning och rendering**

```javascript
// src/adminCreatorReview.js
//
// Granskningsvy för creator-inskick. Alla beslut fattas här av en
// människa; "Kör granskning" är rådgivande och ändrar ingen status.

import { requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const VERDICT_LABELS = { gron: 'Grön', gul: 'Gul', rod: 'Röd' };
const TYPE_LABELS = { prompt: 'Prompt', package: 'Paket' };

function el(selector, root = document) {
    return root.querySelector(selector);
}

function renderConsents(row) {
    const parts = [
        `Publicering: ${row.consent_shared ? 'ja' : 'nej'}`,
        `Distribution till Open/MCP: ${row.consent_distribution ? 'ja' : 'nej'}`,
        `Rättigheter intygade: ${row.rights_attested ? 'ja' : 'nej'}`
    ];
    return parts.join(' · ');
}

function renderFindings(screening) {
    if (!screening || !screening.findings?.length) return '<p>Inga fynd.</p>';
    return '<ul>' + screening.findings.map((finding) =>
        `<li><strong>${finding.kategori} (${finding.allvarlighet}):</strong> ${finding.text}</li>`
    ).join('') + '</ul>';
}

async function loadSubmissions() {
    const statusEl = el('[data-review-status]');
    const listEl = el('[data-review-list]');
    const template = el('[data-review-row-template]');

    statusEl.textContent = 'Laddar inskick...';
    const { data, error } = await supabase.rpc('list_creator_submissions');

    if (error) {
        el('[data-review-denied]').hidden = false;
        statusEl.textContent = `Kunde inte ladda inskick: ${error.message}`;
        return;
    }

    statusEl.textContent = data.length ? `${data.length} inskick väntar.` : 'Inga inskick väntar på granskning.';
    listEl.innerHTML = '';
    listEl.hidden = false;
    data.forEach((row) => listEl.appendChild(renderRow(template, row)));
}
```

- [ ] **Step 4: Skriv radrenderingen med de fem knapparna**

```javascript
function renderRow(template, row) {
    const node = template.content.firstElementChild.cloneNode(true);
    const errorEl = el('[data-review-error]', node);
    const detailEl = el('[data-review-detail]', node);

    el('[data-review-title]', node).textContent = row.title;
    el('[data-review-verdict]', node).textContent =
        row.latest_verdict ? VERDICT_LABELS[row.latest_verdict] : 'Ej granskad';
    el('[data-review-verdict]', node).dataset.verdict = row.latest_verdict || 'none';
    el('[data-review-meta]', node).textContent =
        `${TYPE_LABELS[row.subject_type]} · ${row.creator_display_name || 'Okänd creator'}` +
        (row.item_count ? ` · ${row.item_count} prompts` : '');
    el('[data-review-consents]', node).textContent = renderConsents(row);

    const fail = (message) => {
        errorEl.textContent = message;
        errorEl.hidden = false;
    };

    el('[data-review-open]', node).addEventListener('click', async () => {
        errorEl.hidden = true;
        const { data, error } = await supabase.rpc('get_creator_submission', {
            p_subject_type: row.subject_type,
            p_subject_id: row.subject_id
        });
        if (error) { fail(error.message); return; }
        const latest = data.screenings?.[0];
        detailEl.innerHTML =
            `<pre class="mp-template-preview">${data.content || (data.items || []).map((i) => `${i.title}\n${i.content}`).join('\n\n')}</pre>` +
            renderFindings(latest) +
            (latest?.suggested_feedback ? `<p><em>Förslag till återkoppling:</em> ${latest.suggested_feedback}</p>` : '');
        detailEl.dataset.suggestedFeedback = latest?.suggested_feedback || '';
        detailEl.hidden = false;
    });

    el('[data-review-screen]', node).addEventListener('click', async (event) => {
        errorEl.hidden = true;
        const button = event.currentTarget;
        button.disabled = true;
        button.textContent = 'Granskar...';
        const { data: { session } } = await supabase.auth.getSession();
        try {
            const response = await fetch(
                `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/screen-creator-submission`,
                {
                    method: 'POST',
                    headers: {
                        Authorization: `Bearer ${session.access_token}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ subject_type: row.subject_type, subject_id: row.subject_id })
                }
            );
            const body = await response.json();
            if (!response.ok) { fail(body.error || 'Granskningen misslyckades.'); return; }
            await loadSubmissions();
        } finally {
            button.disabled = false;
            button.textContent = 'Kör granskning';
        }
    });

    el('[data-review-approve]', node).addEventListener('click', async () => {
        errorEl.hidden = true;
        const slug = prompt('Adress (slug) i katalogen:');
        if (!slug) return;
        const rpcName = row.subject_type === 'prompt' ? 'approve_creator_prompt' : 'approve_creator_package';
        const args = row.subject_type === 'prompt'
            ? { p_content_item_id: row.subject_id, p_slug: slug, p_icon_key: 'library', p_color_theme: null }
            : { p_draft_id: row.subject_id, p_slug: slug, p_icon_key: 'files', p_color_theme: null };
        const { error } = await supabase.rpc(rpcName, args);
        if (error) { fail(error.message); return; }
        await loadSubmissions();
    });

    const decide = async (rpcName, promptText) => {
        errorEl.hidden = true;
        const note = prompt(promptText, detailEl.dataset.suggestedFeedback || '');
        if (!note) return;
        const { error } = await supabase.rpc(rpcName, {
            p_subject_type: row.subject_type,
            p_subject_id: row.subject_id,
            p_note: note
        });
        if (error) { fail(error.message); return; }
        await loadSubmissions();
    };

    el('[data-review-changes]', node).addEventListener('click', () =>
        decide('request_changes_creator_submission', 'Vad ska creatorn ändra?'));
    el('[data-review-reject]', node).addEventListener('click', () =>
        decide('reject_creator_submission', 'Varför avslås inskicket?'));

    return node;
}

async function init() {
    const statusEl = el('[data-review-status]');
    if (!statusEl) return;
    if (!requireSupabaseConfig(statusEl)) return;

    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        statusEl.textContent = 'Logga in för att granska inskick.';
        return;
    }

    el('[data-review-refresh]').addEventListener('click', loadSubmissions);
    await loadSubmissions();
}

init();
```

`prompt()` används här medvetet, samma som `adminCreatorProfiles.js` gör för sina inmatningar. Byt inte till en egen modal i denna task.

- [ ] **Step 5: Verifiera i webbläsaren**

Kör `npm run web:dev`, logga in som plattformsägare, gå till `admin.html#creator-granskning`.

Testa i denna ordning:
1. Sidan listar inskick, eller säger att inga väntar.
2. "Visa" fyller detaljvyn med prompttexten.
3. "Kör granskning" ger ett verdikt inom några sekunder, och färgmarkeringen uppdateras.
4. "Begär ändring" med en motivering flyttar posten ur listan.
5. Logga in som en icke-plattformsägare: sektionen visar nekad-vyn, inga inskick.

- [ ] **Step 6: Commit**

```bash
git add admin.html src/adminCreatorReview.js
git commit -m "feat(admin): add creator submission review section"
```

---

### Task 7: Återkoppling till creatorn

**Files:**
- Create: `supabase/migrations/20260823095000_creator_list_review_note.sql`
- Modify: `src/creatorContent.js:60-76` (listrendering), `src/creatorPackages.js:11-28` (kortrendering)
- Modify: `creator-content.html`, `creator-packages.html` (plats för noten i mallarna)

**Interfaces:**
- Consumes: `content_items.review_note` (fanns redan), `creator_package_drafts.review_note` (Task 1).
- Produces: `list_my_creator_prompts()` och `list_my_creator_package_drafts()` returnerar `review_note text`.

- [ ] **Step 1: Utöka de två list-RPC:erna**

Signaturerna är oförändrade (inga argument), men returtabellen växer. `create or replace function` klarar inte en ändrad returtabell — droppa och skapa.

```sql
-- supabase/migrations/20260823095000_creator_list_review_note.sql
-- Utan review_note ser creatorn aldrig varför en ändring begärdes, och
-- "Begär ändring" blir en återvändsgränd.

drop function if exists public.list_my_creator_prompts();

create or replace function public.list_my_creator_prompts()
returns table (
    id uuid,
    title text,
    slug text,
    summary text,
    status text,
    visibility text,
    creator_consent_shared boolean,
    creator_consent_reusable boolean,
    review_note text,
    updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select ci.id, ci.title, ci.slug, ci.summary, ci.status::text, ci.visibility::text,
           ci.creator_consent_shared, ci.creator_consent_reusable, ci.review_note, ci.updated_at
      from public.content_items ci
     where ci.owner_user_id = (select auth.uid())
       and ci.type = 'prompt'
       and ci.module = 'kommun'
     order by ci.updated_at desc;
$$;

revoke all on function public.list_my_creator_prompts() from public;
grant execute on function public.list_my_creator_prompts() to authenticated;
```

Gör motsvarande för `list_my_creator_package_drafts()` — läs dess nuvarande definition i `20260819090000_creator_authoring.sql` och lägg till `d.review_note` sist före `updated_at`.

- [ ] **Step 2: Lägg till platsen i mallarna**

I `creator-content.html`, i radmallen efter statusbadgen:

```html
<p class="mp-hint is-error" data-row-review-note hidden></p>
```

I `creator-packages.html`, i kortmallen på motsvarande plats:

```html
<p class="mp-hint is-error" data-draft-review-note hidden></p>
```

- [ ] **Step 3: Visa noten i creatorContent.js**

I `renderRow`, efter raden som sätter statusbadgen:

```javascript
    const reviewNoteEl = el('[data-row-review-note]', node);
    if (prompt.status === 'draft' && prompt.review_note) {
        reviewNoteEl.textContent = `Skickades tillbaka: ${prompt.review_note}`;
        reviewNoteEl.hidden = false;
    }
```

- [ ] **Step 4: Visa noten i creatorPackages.js**

I `renderDraft`, efter raden som sätter statusbadgen:

```javascript
    const reviewNoteEl = el('[data-draft-review-note]', node);
    if (draft.status === 'draft' && draft.review_note) {
        reviewNoteEl.textContent = `Skickades tillbaka: ${draft.review_note}`;
        reviewNoteEl.hidden = false;
    }
```

- [ ] **Step 5: Verifiera hela rundan**

Kör migrationen. Med dev-servern igång:
1. Som creator: skapa och skicka in en prompt.
2. Som plattformsägare: begär ändring med motiveringen "Lägg till en platshållare för indata."
3. Som creator igen: ladda om `creator-content.html`.

Förväntat: prompten står som Utkast och visar `Skickades tillbaka: Lägg till en platshållare för indata.`

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260823095000_creator_list_review_note.sql src/creatorContent.js src/creatorPackages.js creator-content.html creator-packages.html
git commit -m "feat(creator): show editorial feedback to the creator"
```

---

### Task 8: Attribution på de publika sidorna

**Files:**
- Create: `supabase/migrations/20260823096000_creator_published_content_rpc.sql`
- Modify: `scripts/creator-page-template.mjs:169-171` (nollägena), `scripts/generate-catalog-pages.mjs:131-155` (hämta innehållet)
- Modify: `scripts/catalog-page-template.mjs` ("Av namn"-raden)
- Modify: `scripts/creator-page-template.test.mjs` (nya assertions)

**Interfaces:**
- Consumes: `catalog_prompts.creator_profile_id`, `catalog_packages.creator_profile_id` från Task 1, `creatorUrl()` från `scripts/creator-page-lib.mjs`.
- Produces: `public.list_creator_published_content(p_slug text) returns table(kind text, slug text, title text, summary text)`.

- [ ] **Step 1: Skriv läs-RPC:n**

```sql
-- supabase/migrations/20260823096000_creator_published_content_rpc.sql
-- Fyller creator-sidans två nollägen. Publik läsning: bara publicerat
-- innehåll för en publicerad creator.

create or replace function public.list_creator_published_content(p_slug text)
returns table (
    kind text,
    slug text,
    title text,
    summary text
)
language sql
security definer
set search_path = ''
as $$
    select 'package'::text, cpkg.slug, v.title, v.summary
      from public.catalog_packages cpkg
      join public.creator_profiles prof on prof.id = cpkg.creator_profile_id
      join public.catalog_package_variants v
        on v.package_id = cpkg.id and v.context_key = 'generell'
     where prof.slug = p_slug
       and prof.status = 'published'
       and cpkg.status = 'published'

    union all

    select 'prompt'::text, cp.slug, v.title, v.summary
      from public.catalog_prompts cp
      join public.creator_profiles prof on prof.id = cp.creator_profile_id
      join public.catalog_prompt_variants v
        on v.prompt_id = cp.id and v.context_key = 'generell'
     where prof.slug = p_slug
       and prof.status = 'published'
       and cp.status = 'published'

     order by 1, 3;
$$;

revoke all on function public.list_creator_published_content(text) from public;
grant execute on function public.list_creator_published_content(text) to anon, authenticated;
```

- [ ] **Step 2: Skriv testet för mallen först**

I `scripts/creator-page-template.test.mjs`, lägg till:

```javascript
test('renderCreatorPage listar publicerade paket och prompts', () => {
    const html = renderCreatorPage({
        profile: { slug: 'anna', display_name: 'Anna Ek', bio_short: 'Kort' },
        indexable: true,
        publishedContent: [
            { kind: 'package', slug: 'mitt-paket', title: 'Mitt paket', summary: 'Om paketet' },
            { kind: 'prompt', slug: 'min-prompt', title: 'Min prompt', summary: 'Om prompten' }
        ]
    });
    assert.match(html, /\/paket\/mitt-paket\//);
    assert.match(html, /Min prompt/);
    assert.doesNotMatch(html, /Publicerade paket<\/h2>\s*<p>Inget publicerat/);
});
```

- [ ] **Step 3: Kör testet och se det falla**

Run: `node --test scripts/creator-page-template.test.mjs`
Expected: FAIL — `publishedContent` används inte av mallen än.

- [ ] **Step 4: Byt nollägena mot riktiga listor**

I `scripts/creator-page-template.mjs`, ersätt rad 169–170 (behåll `emptyStateSection('Workshopkrediter')` på rad 171 — den hör till delprojekt 5):

```javascript
function contentSection(heading, items, urlFor) {
    if (!items.length) return emptyStateSection(heading);
    return `<section class="creator-content-section">
            <h2>${escapeHtml(heading)}</h2>
            <ul class="creator-content-list">
                ${items.map((item) => `<li><a href="${escapeHtml(urlFor(item.slug))}">${escapeHtml(item.title)}</a>${item.summary ? ` — ${escapeHtml(item.summary)}` : ''}</li>`).join('\n                ')}
            </ul>
        </section>`;
}
```

Och i `renderCreatorPage`, med `publishedContent = []` som ny parameter med defaultvärde:

```javascript
            ${contentSection('Publicerade paket', publishedContent.filter((i) => i.kind === 'package'), (slug) => `/paket/${slug}/`)}
            ${contentSection('Publicerade prompts', publishedContent.filter((i) => i.kind === 'prompt'), (slug) => `/prompt/${slug}/`)}
```

Kontrollera den faktiska prompt-URL-formen i `scripts/catalog-page-lib.mjs` innan du hårdkodar `/prompt/` — använd den befintliga hjälpfunktionen om det finns en.

- [ ] **Step 5: Kör testet igen**

Run: `node --test scripts/creator-page-template.test.mjs`
Expected: PASS, och de tidigare testerna i filen fortsatt gröna.

- [ ] **Step 6: Hämta innehållet i generatorn**

I `scripts/generate-catalog-pages.mjs`, i loopen som skriver creator-sidor runt rad 144:

```javascript
        const publishedContent = await rpc('list_creator_published_content', { p_slug: profile.slug });
        writePage(
            `creator/${profile.slug}`,
            renderCreatorPage({ profile, indexable: isProfileIndexable(profile), publishedContent })
        );
```

Anpassa efter hur `writePage` och loopen faktiskt ser ut i filen.

- [ ] **Step 7: Lägg "Av namn" på katalogsidorna**

I `scripts/catalog-page-template.mjs`, där paketets och promptens rubrikblock renderas, lägg till när attributionen finns:

```javascript
    const byline = creatorDisplayName
        ? `<p class="catalog-byline">Av <a href="${escapeHtml(creatorUrl(creatorSlug))}">${escapeHtml(creatorDisplayName)}</a></p>`
        : '';
```

Fälten måste följa med i `list_published_packages`/`list_published_prompts`-svaret. Kontrollera om `creator_profile_id` redan returneras efter Task 4 — gör den inte det, lägg till `creator_display_name` och `creator_slug` som returkolumner i en följdmigration och dokumentera det i commit-meddelandet.

- [ ] **Step 8: Generera sidorna och granska**

```bash
node scripts/generate-catalog-pages.mjs
```
Förväntat: samma antal sidor som förut, plus att `dist/creator/<slug>/index.html` för en creator med publicerat innehåll nu innehåller listor istället för nollägen.

Öppna en genererad creator-sida i webbläsaren och kontrollera att länkarna går rätt.

- [ ] **Step 9: Commit**

```bash
git add supabase/migrations/20260823096000_creator_published_content_rpc.sql scripts/creator-page-template.mjs scripts/creator-page-template.test.mjs scripts/generate-catalog-pages.mjs scripts/catalog-page-template.mjs
git commit -m "feat(creator): show published content and byline on public pages"
```

---

### Task 9: Slutverifiering

**Files:**
- Modify: `TODO.md` (markera delprojekt 4)
- Modify: `docs/superpowers/specs/2026-08-18-creator-authoring-design.md` (delprojektlistan)

- [ ] **Step 1: Kör alla nya SQL-tester i följd**

Kör mot länkad produktion eller staging:
- `supabase/tests/creator_review_schema.sql`
- `supabase/tests/creator_review_read.sql`
- `supabase/tests/creator_review_decisions.sql`
- `supabase/tests/catalog_read_creator_gate.sql`

Förväntat: enbart `OK:`-notiser, inga exceptions.

- [ ] **Step 2: Kör MCP-kontraktstestet**

Använd skillen `promptbanken-mcp-contract-test` mot produktion.
Förväntat: de nio publika verktygen svarar oförändrat, och inget creator-innehåll finns i svaren.

- [ ] **Step 3: Kör hela rundan manuellt**

Som creator: skapa prompt, skicka in med båda nya samtyckena. Som plattformsägare: kör granskning, läs fynden, godkänn med en slug. Kontrollera att katalogposten finns som utkast och bär attributionen. Publicera den med `publish_catalog_prompt`. Kör sidgeneratorn och kontrollera att prompten syns på creator-sidan.

Kontrollera sedan gaten en sista gång:
```bash
curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/list_published_prompts" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -H "Content-Type: application/json" \
  -d '{"p_context_keys":["generell"]}' | grep -c "<den nya sluggen>"
```
Förväntat: `0`. Creator-innehållet finns på webben men inte i MCP-vägen.

- [ ] **Step 4: Uppdatera dokumentationen**

I `TODO.md`, markera delprojekt 4 som levererat med dagens datum. I `docs/superpowers/specs/2026-08-18-creator-authoring-design.md`, stryk under punkt 4 i delprojektlistan som levererad.

Lägg till en rad i specen för delprojekt 4 under "Kvarstående för delprojekt 7" om något visade sig annorlunda under bygget.

- [ ] **Step 5: Commit**

```bash
git add TODO.md docs/superpowers/specs/2026-08-18-creator-authoring-design.md
git commit -m "docs: mark delprojekt 4 as delivered"
```

---

## Vad denna plan medvetet inte gör

- Flippar aldrig gaten så creator-innehåll når Open/MCP. Det är delprojekt 7, och kräver att `privacy.html`/`privacy-en.html` avsnitt 2.3 uppdateras först samt att ansökan 1.2.2 är avgjord.
- Återupplivar inte `src/admin.js`. Den är död kod sedan `5a09156` och ska inte byggas vidare på.
- Bygger ingen kandidatsökning för dubletter. Hela katalogen skickas med i promptkontexten, vilket håller till omkring 500 poster.
- Rör inte Workshopkrediter-nolläget på creator-sidan (delprojekt 5).
