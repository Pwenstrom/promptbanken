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
           creator_consent_shared = true,
           creator_consent_reusable = coalesce(p_consent_reusable, false),
           updated_at = now()
     where id = p_content_item_id
       and owner_user_id = (select auth.uid())
       and type = 'prompt'
       and module = 'kommun'
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
       and ci.module = 'kommun'
     order by ci.updated_at desc;
$$;

revoke all on function public.list_my_creator_prompts() from public;
grant execute on function public.list_my_creator_prompts() to authenticated;

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
           and status = 'draft'
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
     where id = p_draft_id and status = 'draft'
     for update;

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

    select count(*) into v_item_count
      from public.creator_package_items
     where draft_id = p_draft_id;

    return jsonb_build_object('draft_id', p_draft_id, 'item_count', v_item_count);
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
       and d.status = 'draft'
    returning cpi.id into v_deleted_id;

    if v_deleted_id is null then
        raise exception 'Raden hittades inte, paketet tillhör inte dig, eller kan inte redigeras i sitt nuvarande läge.';
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
     where id = p_draft_id and status = 'draft'
     for update;

    if v_draft_owner is null or v_draft_owner <> (select auth.uid()) then
        raise exception 'Paketet hittades inte, tillhör inte dig, eller är redan inskickat.';
    end if;

    select count(*) into v_item_count from public.creator_package_items where draft_id = p_draft_id;
    if v_item_count = 0 then
        raise exception 'Paketet behöver minst en prompt innan det kan skickas in.';
    end if;

    perform pg_advisory_xact_lock(hashtext((select auth.uid())::text));

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
