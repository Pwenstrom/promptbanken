# Creator-authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a published creator (delprojekt 2) submit their own prompts and paket-of-own-prompts for review, with two explicit consent flags, feeding the existing `content_items` → catalog copy pattern.

**Architecture:** Extend `content_items` (arbetsytemodellen) with two consent columns and reuse its existing `status`/`visibility` enums for the review flow. Add two small new tables (`creator_package_drafts`, `creator_package_items`) for paket-utkast since the workspace model has no packaging concept. All writes go through `security definer` RPCs (`app_private.*` implementation + `public.*` wrapper, matching `creator_profiles`'s pattern) — no direct table writes from the client. Two new app pages consume the RPCs.

**Tech Stack:** Supabase Postgres (RLS + RPC), vanilla JS (`src/*.js`, no framework), Vite multi-page build.

**Spec:** `docs/superpowers/specs/2026-08-18-creator-authoring-design.md`

## Global Constraints

- Max 8 prompts per paket-utkast (RPC-enforced, not a DB constraint).
- Max 3 paket-utkast med `status = 'review'` samtidigt per creator; publicerade räknas inte.
- Free-planens 3-prompt-tak på arbetsytan gäller oförändrat för creator-inskickade prompts — ingen ny kvot.
- `submit_creator_prompt` kräver `p_consent_shared = true`, annars fel.
- Ingen RPC eller sida i denna plan sätter `status = 'published'` — bara `'review'`. Godkännande är manuellt (delprojekt 4, utanför scope).
- Svenska felmeddelanden genomgående, samma stil som `creator_profiles`-RPC:erna.

---

### Task 1: Migration — content_items-kolumner, paket-tabeller, RLS, RPC:er

**Files:**
- Create: `supabase/migrations/20260819090000_creator_authoring.sql`
- Create: `supabase/tests/creator_authoring.sql`

**Interfaces:**
- Produces (RPC:er konsumeras av Task 2 och 3):
  - `public.submit_creator_prompt(p_content_item_id uuid, p_consent_shared boolean, p_consent_reusable boolean) returns jsonb`
  - `public.withdraw_creator_prompt(p_content_item_id uuid) returns jsonb`
  - `public.list_my_creator_prompts() returns table(id uuid, title text, slug text, summary text, status text, visibility text, creator_consent_shared boolean, creator_consent_reusable boolean, updated_at timestamptz)`
  - `public.upsert_creator_package_draft(p_draft_id uuid, p_title text, p_summary text) returns jsonb`
  - `public.add_prompt_to_package_draft(p_draft_id uuid, p_content_item_id uuid, p_position integer) returns jsonb`
  - `public.remove_prompt_from_package_draft(p_draft_id uuid, p_content_item_id uuid) returns jsonb`
  - `public.reorder_package_draft_items(p_draft_id uuid, p_ordered_ids uuid[]) returns jsonb`
  - `public.submit_creator_package_draft(p_draft_id uuid) returns jsonb`
  - `public.withdraw_creator_package_draft(p_draft_id uuid) returns jsonb`
  - `public.list_my_creator_package_drafts() returns table(id uuid, title text, summary text, status text, item_count integer, updated_at timestamptz)`
  - `public.list_creator_package_draft_items(p_draft_id uuid) returns table(content_item_id uuid, title text, summary text, status text, position integer)`

- [ ] **Step 1: Läs mönsterfilerna**

Läs `supabase/migrations/20260816090000_creator_profiles.sql` (RLS + `security definer`-RPC-mönster, svenska felmeddelanden, `revoke all ... from public` + `grant execute ... to authenticated`) och kolla `content_items`-schemat:

```sql
select column_name, data_type from information_schema.columns
where table_schema='public' and table_name='content_items' order by ordinal_position;
```

`content_items` har redan: `id`, `workspace_id`, `owner_user_id`, `type` (enum `content_item_type`: prompt/routine/checklist/guide/faq/document/template/assistant), `title`, `slug`, `summary`, `content`, `status` (enum `content_status`: draft/review/published/archived), `visibility` (enum `content_visibility`: public/workspace/private), `updated_at`.

- [ ] **Step 2: Skriv kolumnerna på content_items**

```sql
-- supabase/migrations/20260819090000_creator_authoring.sql
-- Creator-authoring: en creator kan skicka in egna prompts och bygga
-- paket av egna prompts för granskning. Se
-- docs/superpowers/specs/2026-08-18-creator-authoring-design.md.

alter table public.content_items
    add column if not exists creator_consent_shared boolean not null default false,
    add column if not exists creator_consent_reusable boolean not null default false;

comment on column public.content_items.creator_consent_shared is
    'Sant om ägaren godkänt att prompten delas i öppna Promptbanken. Krävs för att status kan bli review via submit_creator_prompt.';
comment on column public.content_items.creator_consent_reusable is
    'Sant om ägaren godkänt att andra creators får inkludera denna publicerade prompt i sina egna paket-utkast.';
```

- [ ] **Step 3: Skriv paket-tabellerna och RLS**

```sql
create table if not exists public.creator_package_drafts (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    title text not null,
    summary text,
    status text not null default 'draft' check (status in ('draft', 'review', 'published', 'archived')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint creator_package_drafts_title_not_blank check (trim(title) <> '')
);

alter table public.creator_package_drafts enable row level security;

drop policy if exists "creator_package_drafts_select_own" on public.creator_package_drafts;
create policy "creator_package_drafts_select_own"
    on public.creator_package_drafts for select
    to authenticated
    using (owner_user_id = (select auth.uid()));

-- Ingen insert/update/delete-policy: allt går via RPC:erna nedan.
grant select on public.creator_package_drafts to authenticated;

create table if not exists public.creator_package_items (
    id uuid primary key default gen_random_uuid(),
    draft_id uuid not null references public.creator_package_drafts(id) on delete cascade,
    content_item_id uuid not null references public.content_items(id) on delete cascade,
    position integer not null,
    created_at timestamptz not null default now(),
    unique (draft_id, content_item_id)
);

alter table public.creator_package_items enable row level security;

drop policy if exists "creator_package_items_select_own" on public.creator_package_items;
create policy "creator_package_items_select_own"
    on public.creator_package_items for select
    to authenticated
    using (
        exists (
            select 1 from public.creator_package_drafts d
            where d.id = creator_package_items.draft_id
              and d.owner_user_id = (select auth.uid())
        )
    );

grant select on public.creator_package_items to authenticated;

create index if not exists creator_package_drafts_owner_status_idx
    on public.creator_package_drafts (owner_user_id, status);

create index if not exists creator_package_items_draft_idx
    on public.creator_package_items (draft_id);
```

- [ ] **Step 4: Skriv prompt-RPC:erna**

```sql
create or replace function app_private.submit_creator_prompt(
    p_content_item_id uuid,
    p_consent_shared boolean,
    p_consent_reusable boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_updated_id uuid;
begin
    if coalesce(p_consent_shared, false) is not true then
        raise exception 'Du måste godkänna att prompten delas i öppna Promptbanken innan den kan skickas in.';
    end if;

    update public.content_items
       set status = 'review',
           visibility = 'public',
           creator_consent_shared = true,
           creator_consent_reusable = coalesce(p_consent_reusable, false),
           updated_at = now()
     where id = p_content_item_id
       and owner_user_id = (select auth.uid())
       and type = 'prompt'
       and status <> 'published'
    returning id into v_updated_id;

    if v_updated_id is null then
        raise exception 'Prompten hittades inte, tillhör inte dig, eller är redan publicerad.';
    end if;

    return jsonb_build_object('id', v_updated_id, 'status', 'review');
end;
$$;

create or replace function public.submit_creator_prompt(
    p_content_item_id uuid,
    p_consent_shared boolean,
    p_consent_reusable boolean
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.submit_creator_prompt(p_content_item_id, p_consent_shared, p_consent_reusable);
$$;

revoke all on function public.submit_creator_prompt(uuid, boolean, boolean) from public;
grant execute on function public.submit_creator_prompt(uuid, boolean, boolean) to authenticated;

create or replace function app_private.withdraw_creator_prompt(p_content_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_updated_id uuid;
begin
    update public.content_items
       set status = 'draft',
           visibility = 'private',
           creator_consent_shared = false,
           creator_consent_reusable = false,
           updated_at = now()
     where id = p_content_item_id
       and owner_user_id = (select auth.uid())
       and status = 'review'
    returning id into v_updated_id;

    if v_updated_id is null then
        raise exception 'Prompten hittades inte, tillhör inte dig, eller är inte under granskning (publicerat innehåll kan inte dras tillbaka härifrån).';
    end if;

    return jsonb_build_object('id', v_updated_id, 'status', 'draft');
end;
$$;

create or replace function public.withdraw_creator_prompt(p_content_item_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.withdraw_creator_prompt(p_content_item_id);
$$;

revoke all on function public.withdraw_creator_prompt(uuid) from public;
grant execute on function public.withdraw_creator_prompt(uuid) to authenticated;

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
    updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select ci.id, ci.title, ci.slug, ci.summary, ci.status::text, ci.visibility::text,
           ci.creator_consent_shared, ci.creator_consent_reusable, ci.updated_at
      from public.content_items ci
     where ci.owner_user_id = (select auth.uid())
       and ci.type = 'prompt'
     order by ci.updated_at desc;
$$;

revoke all on function public.list_my_creator_prompts() from public;
grant execute on function public.list_my_creator_prompts() to authenticated;
```

- [ ] **Step 5: Skriv paket-draft-RPC:erna**

```sql
create or replace function app_private.upsert_creator_package_draft(
    p_draft_id uuid,
    p_title text,
    p_summary text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    if trim(coalesce(p_title, '')) = '' then
        raise exception 'Paketet behöver en titel.';
    end if;

    if p_draft_id is null then
        insert into public.creator_package_drafts (owner_user_id, title, summary)
        values ((select auth.uid()), trim(p_title), nullif(trim(coalesce(p_summary, '')), ''))
        returning id into v_id;
    else
        update public.creator_package_drafts
           set title = trim(p_title),
               summary = nullif(trim(coalesce(p_summary, '')), ''),
               updated_at = now()
         where id = p_draft_id
           and owner_user_id = (select auth.uid())
           and status in ('draft', 'review')
        returning id into v_id;

        if v_id is null then
            raise exception 'Paketet hittades inte, tillhör inte dig, eller kan inte redigeras i sitt nuvarande läge.';
        end if;
    end if;

    return jsonb_build_object('id', v_id);
end;
$$;

create or replace function public.upsert_creator_package_draft(
    p_draft_id uuid default null,
    p_title text default null,
    p_summary text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.upsert_creator_package_draft(p_draft_id, p_title, p_summary);
$$;

revoke all on function public.upsert_creator_package_draft(uuid, text, text) from public;
grant execute on function public.upsert_creator_package_draft(uuid, text, text) to authenticated;

create or replace function app_private.add_prompt_to_package_draft(
    p_draft_id uuid,
    p_content_item_id uuid,
    p_position integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_draft_owner uuid;
    v_item_count integer;
    v_item_eligible boolean;
begin
    select owner_user_id into v_draft_owner
      from public.creator_package_drafts
     where id = p_draft_id and status in ('draft', 'review');

    if v_draft_owner is null or v_draft_owner <> (select auth.uid()) then
        raise exception 'Paketet hittades inte, tillhör inte dig, eller kan inte redigeras i sitt nuvarande läge.';
    end if;

    select exists (
        select 1 from public.content_items ci
         where ci.id = p_content_item_id
           and ci.type = 'prompt'
           and (
               ci.owner_user_id = (select auth.uid())
               or (ci.status = 'published' and ci.creator_consent_reusable = true)
           )
    ) into v_item_eligible;

    if not v_item_eligible then
        raise exception 'Prompten kan inte läggas till: den är varken din egen eller en publicerad prompt som får återanvändas.';
    end if;

    select count(*) into v_item_count
      from public.creator_package_items
     where draft_id = p_draft_id;

    if v_item_count >= 8 then
        raise exception 'Ett paket kan innehålla högst 8 prompts.';
    end if;

    insert into public.creator_package_items (draft_id, content_item_id, position)
    values (p_draft_id, p_content_item_id, coalesce(p_position, v_item_count))
    on conflict (draft_id, content_item_id) do nothing;

    return jsonb_build_object('draft_id', p_draft_id, 'item_count', v_item_count + 1);
end;
$$;

create or replace function public.add_prompt_to_package_draft(
    p_draft_id uuid,
    p_content_item_id uuid,
    p_position integer default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.add_prompt_to_package_draft(p_draft_id, p_content_item_id, p_position);
$$;

revoke all on function public.add_prompt_to_package_draft(uuid, uuid, integer) from public;
grant execute on function public.add_prompt_to_package_draft(uuid, uuid, integer) to authenticated;

create or replace function app_private.remove_prompt_from_package_draft(
    p_draft_id uuid,
    p_content_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_deleted_id uuid;
begin
    delete from public.creator_package_items cpi
     using public.creator_package_drafts d
     where cpi.draft_id = d.id
       and cpi.draft_id = p_draft_id
       and cpi.content_item_id = p_content_item_id
       and d.owner_user_id = (select auth.uid())
    returning cpi.id into v_deleted_id;

    if v_deleted_id is null then
        raise exception 'Raden hittades inte eller paketet tillhör inte dig.';
    end if;

    return jsonb_build_object('removed', true);
end;
$$;

create or replace function public.remove_prompt_from_package_draft(
    p_draft_id uuid,
    p_content_item_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.remove_prompt_from_package_draft(p_draft_id, p_content_item_id);
$$;

revoke all on function public.remove_prompt_from_package_draft(uuid, uuid) from public;
grant execute on function public.remove_prompt_from_package_draft(uuid, uuid) to authenticated;

create or replace function app_private.reorder_package_draft_items(
    p_draft_id uuid,
    p_ordered_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_draft_owner uuid;
    v_id uuid;
    v_position integer := 0;
begin
    select owner_user_id into v_draft_owner
      from public.creator_package_drafts
     where id = p_draft_id;

    if v_draft_owner is null or v_draft_owner <> (select auth.uid()) then
        raise exception 'Paketet hittades inte eller tillhör inte dig.';
    end if;

    foreach v_id in array coalesce(p_ordered_ids, '{}'::uuid[])
    loop
        update public.creator_package_items
           set position = v_position
         where draft_id = p_draft_id
           and content_item_id = v_id;
        v_position := v_position + 1;
    end loop;

    return jsonb_build_object('draft_id', p_draft_id, 'reordered', v_position);
end;
$$;

create or replace function public.reorder_package_draft_items(
    p_draft_id uuid,
    p_ordered_ids uuid[]
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.reorder_package_draft_items(p_draft_id, p_ordered_ids);
$$;

revoke all on function public.reorder_package_draft_items(uuid, uuid[]) from public;
grant execute on function public.reorder_package_draft_items(uuid, uuid[]) to authenticated;

create or replace function app_private.submit_creator_package_draft(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_draft_owner uuid;
    v_item_count integer;
    v_review_count integer;
begin
    select owner_user_id into v_draft_owner
      from public.creator_package_drafts
     where id = p_draft_id and status = 'draft';

    if v_draft_owner is null or v_draft_owner <> (select auth.uid()) then
        raise exception 'Paketet hittades inte, tillhör inte dig, eller är redan inskickat.';
    end if;

    select count(*) into v_item_count from public.creator_package_items where draft_id = p_draft_id;
    if v_item_count = 0 then
        raise exception 'Paketet behöver minst en prompt innan det kan skickas in.';
    end if;

    select count(*) into v_review_count
      from public.creator_package_drafts
     where owner_user_id = (select auth.uid()) and status = 'review';
    if v_review_count >= 3 then
        raise exception 'Du har redan 3 paket under granskning. Dra tillbaka eller vänta på granskning av ett annat paket innan du skickar in fler.';
    end if;

    update public.creator_package_drafts
       set status = 'review', updated_at = now()
     where id = p_draft_id;

    return jsonb_build_object('id', p_draft_id, 'status', 'review');
end;
$$;

create or replace function public.submit_creator_package_draft(p_draft_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.submit_creator_package_draft(p_draft_id);
$$;

revoke all on function public.submit_creator_package_draft(uuid) from public;
grant execute on function public.submit_creator_package_draft(uuid) to authenticated;

create or replace function app_private.withdraw_creator_package_draft(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_updated_id uuid;
begin
    update public.creator_package_drafts
       set status = 'draft', updated_at = now()
     where id = p_draft_id
       and owner_user_id = (select auth.uid())
       and status = 'review'
    returning id into v_updated_id;

    if v_updated_id is null then
        raise exception 'Paketet hittades inte, tillhör inte dig, eller är inte under granskning (publicerade paket kan inte dras tillbaka härifrån).';
    end if;

    return jsonb_build_object('id', v_updated_id, 'status', 'draft');
end;
$$;

create or replace function public.withdraw_creator_package_draft(p_draft_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.withdraw_creator_package_draft(p_draft_id);
$$;

revoke all on function public.withdraw_creator_package_draft(uuid) from public;
grant execute on function public.withdraw_creator_package_draft(uuid) to authenticated;

create or replace function public.list_my_creator_package_drafts()
returns table (
    id uuid,
    title text,
    summary text,
    status text,
    item_count integer,
    updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select d.id, d.title, d.summary, d.status,
           (select count(*)::integer from public.creator_package_items i where i.draft_id = d.id),
           d.updated_at
      from public.creator_package_drafts d
     where d.owner_user_id = (select auth.uid())
     order by d.updated_at desc;
$$;

revoke all on function public.list_my_creator_package_drafts() from public;
grant execute on function public.list_my_creator_package_drafts() to authenticated;

create or replace function app_private.list_creator_package_draft_items(p_draft_id uuid)
returns table (
    content_item_id uuid,
    title text,
    summary text,
    status text,
    position integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not exists (
        select 1 from public.creator_package_drafts
         where id = p_draft_id and owner_user_id = (select auth.uid())
    ) then
        raise exception 'Paketet hittades inte eller tillhör inte dig.';
    end if;

    return query
        select ci.id, ci.title, ci.summary, ci.status::text, cpi.position
          from public.creator_package_items cpi
          join public.content_items ci on ci.id = cpi.content_item_id
         where cpi.draft_id = p_draft_id
         order by cpi.position;
end;
$$;

create or replace function public.list_creator_package_draft_items(p_draft_id uuid)
returns table (
    content_item_id uuid,
    title text,
    summary text,
    status text,
    position integer
)
language sql
security invoker
set search_path = ''
as $$
    select * from app_private.list_creator_package_draft_items(p_draft_id);
$$;

revoke all on function public.list_creator_package_draft_items(uuid) from public;
grant execute on function public.list_creator_package_draft_items(uuid) to authenticated;
```

- [ ] **Step 6: Skriv verifieringsfilen**

```sql
-- supabase/tests/creator_authoring.sql
-- Manuell/CI-körd kontroll. Kör mot en databas med migrationen applicerad.
-- Förutsätter två testanvändare (byt ut UUID:erna mot riktiga auth.users-id:n
-- i din testmiljö, t.ex. via seed-test-users.mjs-mönstret).

-- 1. submit_creator_prompt vägrar utan samtycke
do $$
begin
    begin
        perform app_private.submit_creator_prompt(gen_random_uuid(), false, false);
        raise exception 'FEL: submit_creator_prompt borde ha kastat fel utan samtycke';
    exception when others then
        if sqlerrm not like '%godkänna%' then
            raise;
        end if;
    end;
end $$;

-- 2. add_prompt_to_package_draft stoppar vid 8 prompts (strukturell kontroll,
-- kör mot en riktig draft med 8 redan tillagda rader i din testmiljö och
-- verifiera att rad 9 kastar 'högst 8 prompts').

-- 3. submit_creator_package_draft stoppar vid 3 samtidiga review-paket
-- (skapa 3 drafts, submit:a alla tre, försök submit:a en fjärde, förvänta fel
-- som matchar '%3 paket under granskning%').

-- 4. RLS: en annan användares session kan inte se draften
-- (sätt session till user B, kör `select * from creator_package_drafts
-- where id = '<user A:s draft-id>'` — förvänta 0 rader).
```

- [ ] **Step 7: Läs igenom migrationen en gång till**

Kontrollera: alla `public.*`-RPC:er har `revoke all ... from public` + `grant execute ... to authenticated` (aldrig `anon`). Alla `app_private.*`-funktioner har `security definer, set search_path = ''`. Alla felmeddelanden är på svenska. Inget skriver `status = 'published'` någonstans.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260819090000_creator_authoring.sql supabase/tests/creator_authoring.sql
git commit -m "feat: add creator-authoring migration (content_items consent columns, package drafts, RPCs)"
```

---

### Task 2: `creator-content.html` — mina prompts

**Files:**
- Create: `creator-content.html`
- Create: `src/creatorContent.js`
- Modify: `vite.config.js`

**Interfaces:**
- Consumes: `list_my_creator_prompts()`, `submit_creator_prompt(p_content_item_id, p_consent_shared, p_consent_reusable)`, `withdraw_creator_prompt(p_content_item_id)` (Task 1).
- Produces: nothing consumed by later tasks (leaf page).

- [ ] **Step 1: Läs mönsterfilerna**

Läs `creator.html` + `src/creatorProfile.js` för sidmönstret: `.workspace-page`/`.workspace-topbar`/`.workspace-shell` (redan stylat i `style.css`), inloggningskoll som visar `[data-creator-login-needed]` om ingen session finns, Supabase-klienten importeras från `src/supabaseClient.js` (kolla exakt exportnamn i den filen innan du skriver importen).

- [ ] **Step 2: Bygg sidan**

```html
<!-- creator-content.html -->
<!DOCTYPE html>
<html lang="sv">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Mina prompts | Promptbanken</title>
    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <meta name="robots" content="noindex">
    <link rel="stylesheet" href="style.css">
</head>
<body class="workspace-page">
    <header class="workspace-topbar">
        <a class="workspace-brand" href="index.html">Promptbanken</a>
        <nav>
            <a href="creator.html">Min creator-profil</a>
            <strong data-creator-content-user-email>-</strong>
            <button type="button" data-creator-content-logout>Logga ut</button>
        </nav>
    </header>

    <main class="workspace-shell" aria-labelledby="creator-content-title">
        <div class="workspace-heading">
            <div>
                <p class="workspace-kicker">Skicka in för granskning</p>
                <h1 id="creator-content-title">Mina prompts</h1>
            </div>
        </div>

        <p class="workspace-status" role="status" data-creator-content-status>Laddar...</p>

        <section class="workspace-empty" data-creator-content-login-needed hidden>
            <h1>Du är inte inloggad</h1>
            <p>Logga in för att se och skicka in dina prompts.</p>
            <p><a href="login.html">Till inloggningen</a></p>
        </section>

        <div data-creator-content-list hidden></div>

        <template data-creator-content-row-template>
            <article class="workspace-section" data-row-content-item-id>
                <div class="workspace-section-heading">
                    <h2 data-row-title>-</h2>
                    <strong data-row-status-badge>-</strong>
                </div>
                <p data-row-summary></p>
                <div data-row-submit-form hidden>
                    <label><input type="checkbox" data-row-consent-shared> Jag godkänner att prompten delas i öppna Promptbanken</label>
                    <label><input type="checkbox" data-row-consent-reusable> Andra creators får återanvända den i sina paket</label>
                    <p data-row-error role="alert" hidden></p>
                    <button type="button" data-row-submit-btn>Skicka in för granskning</button>
                </div>
                <button type="button" data-row-withdraw-btn hidden>Dra tillbaka</button>
            </article>
        </template>
    </main>

    <script type="module" src="src/creatorContent.js"></script>
</body>
</html>
```

- [ ] **Step 3: Bygg modulen**

```javascript
// src/creatorContent.js
import { supabase } from './supabaseClient.js';

const STATUS_LABELS = { draft: 'Utkast', review: 'Under granskning', published: 'Publicerad', archived: 'Arkiverad' };

function el(selector, root = document) {
    return root.querySelector(selector);
}

function renderRow(template, prompt) {
    const node = template.content.firstElementChild.cloneNode(true);
    node.dataset.rowContentItemId = prompt.id;
    el('[data-row-title]', node).textContent = prompt.title;
    el('[data-row-summary]', node).textContent = prompt.summary || '';
    el('[data-row-status-badge]', node).textContent = STATUS_LABELS[prompt.status] || prompt.status;

    const submitForm = el('[data-row-submit-form]', node);
    const withdrawBtn = el('[data-row-withdraw-btn]', node);

    if (prompt.status === 'draft') {
        submitForm.hidden = false;
        const consentShared = el('[data-row-consent-shared]', node);
        const consentReusable = el('[data-row-consent-reusable]', node);
        const submitBtn = el('[data-row-submit-btn]', node);
        const errorEl = el('[data-row-error]', node);

        const syncSubmitEnabled = () => { submitBtn.disabled = !consentShared.checked; };
        consentShared.addEventListener('change', syncSubmitEnabled);
        syncSubmitEnabled();

        submitBtn.addEventListener('click', async () => {
            errorEl.hidden = true;
            const { error } = await supabase.rpc('submit_creator_prompt', {
                p_content_item_id: prompt.id,
                p_consent_shared: consentShared.checked,
                p_consent_reusable: consentReusable.checked
            });
            if (error) {
                errorEl.textContent = error.message;
                errorEl.hidden = false;
                return;
            }
            await loadPrompts();
        });
    } else if (prompt.status === 'review') {
        withdrawBtn.hidden = false;
        withdrawBtn.addEventListener('click', async () => {
            const { error } = await supabase.rpc('withdraw_creator_prompt', { p_content_item_id: prompt.id });
            if (error) {
                alert(error.message);
                return;
            }
            await loadPrompts();
        });
    }

    return node;
}

async function loadPrompts() {
    const statusEl = el('[data-creator-content-status]');
    const listEl = el('[data-creator-content-list]');
    const template = el('[data-creator-content-row-template]');

    statusEl.textContent = 'Laddar...';
    const { data, error } = await supabase.rpc('list_my_creator_prompts');
    if (error) {
        statusEl.textContent = `Kunde inte ladda dina prompts: ${error.message}`;
        return;
    }

    statusEl.textContent = data.length ? '' : 'Du har inga prompts i din personliga arbetsyta ännu.';
    listEl.innerHTML = '';
    data.forEach((prompt) => listEl.appendChild(renderRow(template, prompt)));
    listEl.hidden = false;
}

async function init() {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        el('[data-creator-content-login-needed]').hidden = false;
        el('[data-creator-content-status]').hidden = true;
        return;
    }

    el('[data-creator-content-user-email]').textContent = session.user.email || '-';
    el('[data-creator-content-logout]').addEventListener('click', async () => {
        await supabase.auth.signOut();
        window.location.href = 'login.html';
    });

    await loadPrompts();
}

init();
```

- [ ] **Step 4: Registrera sidan i bygget**

I `vite.config.js`, i `build.rollupOptions.input`, lägg till (bredvid `creator: resolve(__dirname, 'creator.html')`):

```javascript
        'creator-content': resolve(__dirname, 'creator-content.html'),
```

- [ ] **Step 5: Verifiera**

Kör: `npm run build` — förväntat: lyckas, `dist/creator-content.html` finns.
Manuell verifiering (kräver inloggad session + minst en egen prompt i personlig arbetsyta): öppna sidan, se listan, kryssa i obligatorisk samtyckesruta, skicka in, se statusbadge byta till "Under granskning", dra tillbaka, se den bli "Utkast" igen.

- [ ] **Step 6: Commit**

```bash
git add creator-content.html src/creatorContent.js vite.config.js
git commit -m "feat: add creator-content page for submitting own prompts"
```

---

### Task 3: `creator-packages.html` — mina paket

**Files:**
- Create: `creator-packages.html`
- Create: `src/creatorPackages.js`
- Modify: `vite.config.js`

**Interfaces:**
- Consumes: `list_my_creator_package_drafts()`, `list_creator_package_draft_items(p_draft_id)`, `upsert_creator_package_draft(p_draft_id, p_title, p_summary)`, `add_prompt_to_package_draft(p_draft_id, p_content_item_id, p_position)`, `remove_prompt_from_package_draft(p_draft_id, p_content_item_id)`, `submit_creator_package_draft(p_draft_id)`, `withdraw_creator_package_draft(p_draft_id)` (Task 1), `list_my_creator_prompts()` (Task 1, för att välja bland egna prompts i paketbyggaren).
- Produces: nothing consumed by later tasks (leaf page).

- [ ] **Step 1: Läs mönsterfilerna**

Samma bas som Task 2 — `creator.html`/`src/creatorProfile.js` för sidskal och inloggningskoll.

- [ ] **Step 2: Bygg sidan**

```html
<!-- creator-packages.html -->
<!DOCTYPE html>
<html lang="sv">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Mina paket | Promptbanken</title>
    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <meta name="robots" content="noindex">
    <link rel="stylesheet" href="style.css">
</head>
<body class="workspace-page">
    <header class="workspace-topbar">
        <a class="workspace-brand" href="index.html">Promptbanken</a>
        <nav>
            <a href="creator.html">Min creator-profil</a>
            <a href="creator-content.html">Mina prompts</a>
            <strong data-creator-packages-user-email>-</strong>
            <button type="button" data-creator-packages-logout>Logga ut</button>
        </nav>
    </header>

    <main class="workspace-shell" aria-labelledby="creator-packages-title">
        <div class="workspace-heading">
            <div>
                <p class="workspace-kicker">Bygg av egna prompts</p>
                <h1 id="creator-packages-title">Mina paket</h1>
            </div>
        </div>

        <p class="workspace-status" role="status" data-creator-packages-status>Laddar...</p>

        <section class="workspace-empty" data-creator-packages-login-needed hidden>
            <h1>Du är inte inloggad</h1>
            <p>Logga in för att bygga och skicka in paket.</p>
            <p><a href="login.html">Till inloggningen</a></p>
        </section>

        <div data-creator-packages-content hidden>
            <section class="workspace-section">
                <h2>Nytt paket</h2>
                <label>Titel <input type="text" data-new-draft-title></label>
                <label>Beskrivning <textarea data-new-draft-summary rows="2"></textarea></label>
                <p data-new-draft-error role="alert" hidden></p>
                <button type="button" data-new-draft-btn>Skapa paket-utkast</button>
            </section>

            <div data-draft-list></div>
        </div>

        <template data-draft-row-template>
            <article class="workspace-section" data-draft-id>
                <div class="workspace-section-heading">
                    <h2 data-draft-title>-</h2>
                    <strong data-draft-status-badge>-</strong>
                </div>
                <p data-draft-summary></p>
                <p data-draft-count-hint></p>
                <div data-draft-items></div>
                <div data-draft-add-row hidden>
                    <select data-draft-add-select></select>
                    <button type="button" data-draft-add-btn>Lägg till</button>
                </div>
                <p data-draft-error role="alert" hidden></p>
                <button type="button" data-draft-submit-btn hidden>Skicka in för granskning</button>
                <button type="button" data-draft-withdraw-btn hidden>Dra tillbaka</button>
            </article>
        </template>

        <template data-draft-item-template>
            <div data-item-content-item-id>
                <span data-item-title></span>
                <button type="button" data-item-remove-btn hidden>Ta bort</button>
            </div>
        </template>
    </main>

    <script type="module" src="src/creatorPackages.js"></script>
</body>
</html>
```

- [ ] **Step 3: Bygg modulen**

```javascript
// src/creatorPackages.js
import { supabase } from './supabaseClient.js';

const STATUS_LABELS = { draft: 'Utkast', review: 'Under granskning', published: 'Publicerad', archived: 'Arkiverad' };
const MAX_ITEMS = 8;

function el(selector, root = document) {
    return root.querySelector(selector);
}

async function renderDraft(cardTemplate, itemTemplate, draft, ownPrompts) {
    const node = cardTemplate.content.firstElementChild.cloneNode(true);
    node.dataset.draftId = draft.id;
    el('[data-draft-title]', node).textContent = draft.title;
    el('[data-draft-summary]', node).textContent = draft.summary || '';
    el('[data-draft-status-badge]', node).textContent = STATUS_LABELS[draft.status] || draft.status;

    const { data: items, error: itemsError } = await supabase.rpc('list_creator_package_draft_items', { p_draft_id: draft.id });
    const itemList = itemsError ? [] : items;

    const countHint = el('[data-draft-count-hint]', node);
    countHint.textContent = `${itemList.length}/${MAX_ITEMS} prompts` + (itemList.length >= 3 && itemList.length <= 6 ? ' — lagom paket' : itemList.length < 3 ? ' — 3–6 prompts brukar vara ett lagom paket' : '');

    const itemsEl = el('[data-draft-items]', node);
    itemList.forEach((item) => {
        const row = itemTemplate.content.firstElementChild.cloneNode(true);
        row.dataset.itemContentItemId = item.content_item_id;
        el('[data-item-title]', row).textContent = item.title;
        if (draft.status === 'draft') {
            const removeBtn = el('[data-item-remove-btn]', row);
            removeBtn.hidden = false;
            removeBtn.addEventListener('click', async () => {
                const { error } = await supabase.rpc('remove_prompt_from_package_draft', {
                    p_draft_id: draft.id,
                    p_content_item_id: item.content_item_id
                });
                if (error) { alert(error.message); return; }
                await loadDrafts();
            });
        }
        itemsEl.appendChild(row);
    });

    if (draft.status === 'draft') {
        const addRow = el('[data-draft-add-row]', node);
        const submitBtn = el('[data-draft-submit-btn]', node);
        const errorEl = el('[data-draft-error]', node);

        if (itemList.length < MAX_ITEMS) {
            addRow.hidden = false;
            const select = el('[data-draft-add-select]', node);
            const addedIds = new Set(itemList.map((i) => i.content_item_id));
            ownPrompts.filter((p) => !addedIds.has(p.id)).forEach((p) => {
                const option = document.createElement('option');
                option.value = p.id;
                option.textContent = `${p.title} (${STATUS_LABELS[p.status] || p.status})`;
                select.appendChild(option);
            });
            el('[data-draft-add-btn]', node).addEventListener('click', async () => {
                if (!select.value) return;
                const { error } = await supabase.rpc('add_prompt_to_package_draft', {
                    p_draft_id: draft.id,
                    p_content_item_id: select.value,
                    p_position: itemList.length
                });
                if (error) { alert(error.message); return; }
                await loadDrafts();
            });
        }

        submitBtn.hidden = false;
        submitBtn.addEventListener('click', async () => {
            errorEl.hidden = true;
            const { error } = await supabase.rpc('submit_creator_package_draft', { p_draft_id: draft.id });
            if (error) {
                errorEl.textContent = error.message;
                errorEl.hidden = false;
                return;
            }
            await loadDrafts();
        });
    } else if (draft.status === 'review') {
        const withdrawBtn = el('[data-draft-withdraw-btn]', node);
        withdrawBtn.hidden = false;
        withdrawBtn.addEventListener('click', async () => {
            const { error } = await supabase.rpc('withdraw_creator_package_draft', { p_draft_id: draft.id });
            if (error) { alert(error.message); return; }
            await loadDrafts();
        });
    }

    return node;
}

async function loadDrafts() {
    const statusEl = el('[data-creator-packages-status]');
    const listEl = el('[data-draft-list]');
    const cardTemplate = el('[data-draft-row-template]');
    const itemTemplate = el('[data-draft-item-template]');

    statusEl.textContent = 'Laddar...';
    const [{ data: drafts, error: draftsError }, { data: ownPrompts, error: promptsError }] = await Promise.all([
        supabase.rpc('list_my_creator_package_drafts'),
        supabase.rpc('list_my_creator_prompts')
    ]);

    if (draftsError || promptsError) {
        statusEl.textContent = `Kunde inte ladda paket: ${(draftsError || promptsError).message}`;
        return;
    }

    statusEl.textContent = drafts.length ? '' : 'Du har inga paket-utkast ännu.';
    listEl.innerHTML = '';
    for (const draft of drafts) {
        listEl.appendChild(await renderDraft(cardTemplate, itemTemplate, draft, ownPrompts));
    }
}

function registerNewDraftForm() {
    const titleInput = el('[data-new-draft-title]');
    const summaryInput = el('[data-new-draft-summary]');
    const errorEl = el('[data-new-draft-error]');

    el('[data-new-draft-btn]').addEventListener('click', async () => {
        errorEl.hidden = true;
        const { error } = await supabase.rpc('upsert_creator_package_draft', {
            p_title: titleInput.value,
            p_summary: summaryInput.value
        });
        if (error) {
            errorEl.textContent = error.message;
            errorEl.hidden = false;
            return;
        }
        titleInput.value = '';
        summaryInput.value = '';
        await loadDrafts();
    });
}

async function init() {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        el('[data-creator-packages-login-needed]').hidden = false;
        el('[data-creator-packages-status]').hidden = true;
        return;
    }

    el('[data-creator-packages-user-email]').textContent = session.user.email || '-';
    el('[data-creator-packages-logout]').addEventListener('click', async () => {
        await supabase.auth.signOut();
        window.location.href = 'login.html';
    });

    el('[data-creator-packages-content]').hidden = false;
    registerNewDraftForm();
    await loadDrafts();
}

init();
```

- [ ] **Step 4: Registrera sidan i bygget**

I `vite.config.js`, i `build.rollupOptions.input`:

```javascript
        'creator-packages': resolve(__dirname, 'creator-packages.html'),
```

- [ ] **Step 5: Verifiera**

Kör: `npm run build` — förväntat: lyckas, `dist/creator-packages.html` finns.
Manuell verifiering: skapa paket-utkast, lägg till en egen prompt, se räknaren "1/8", ta bort den, skicka in ett paket med minst en prompt, se statusbadge bli "Under granskning", försök skicka in ett fjärde samtidigt-i-review-paket och se felmeddelandet om 3-taket.

- [ ] **Step 6: Commit**

```bash
git add creator-packages.html src/creatorPackages.js vite.config.js
git commit -m "feat: add creator-packages page for building packages of own prompts"
```

---

### Task 4: Länka ihop från creator.html

**Files:**
- Modify: `creator.html`

**Interfaces:**
- Consumes: inget nytt (ren länkning).

- [ ] **Step 1: Lägg till navigationslänkar**

I `creator.html`, i `<nav>` inuti `.workspace-topbar` (bredvid `Adminöversikt`-länken), lägg till:

```html
            <a href="creator-content.html">Mina prompts</a>
            <a href="creator-packages.html">Mina paket</a>
```

- [ ] **Step 2: Verifiera**

Öppna `creator.html` inloggad, klicka igenom till båda nya sidorna, klicka tillbaka.

- [ ] **Step 3: Commit**

```bash
git add creator.html
git commit -m "feat: link creator-content and creator-packages from creator profile page"
```

---

## Self-review

- **Spec-täckning:** samtyckesflaggor → Task 1 Step 2/4. Paket-utkast + 8-tak + 3-review-tak → Task 1 Step 3/5. RPC-namnkonvention → Task 1 (matchar `creator_profiles`). UI för prompts → Task 2. UI för paket → Task 3. Länkning från profilsidan → Task 4. SQL-tester → Task 1 Step 6. Allt i "Ingår"-listan i specen har en task.
- **Placeholders:** inga TBD/TODO kvar; alla kodblock är fullständiga.
- **Typkonsekvens:** RPC-namn och parameternamn (`p_content_item_id`, `p_draft_id`, `p_consent_shared`, `p_consent_reusable`) används identiskt i migration (Task 1) och JS-anrop (Task 2/3). `STATUS_LABELS`-nycklarna matchar `content_status`/draft-status-strängarna i båda JS-filerna.
