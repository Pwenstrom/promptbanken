-- 20260717090000_valvet_write_rpcs_search_path_hardening.sql
-- Säkerhetsgranskning av push:en (20260716102000/20260716102500) flaggade
-- att fyra SECURITY DEFINER-funktioner satte `search_path = public,
-- app_private, pg_temp` istället för `''`. Alla referenser i funktionskropparna
-- är redan schema-kvalificerade (public.content_items, app_private.mcp_write_attempts
-- osv.) — inbyggda funktioner (gen_random_uuid, now, coalesce, set_config)
-- ligger i pg_catalog, som alltid söks implicit oavsett search_path-värde.
-- Ingen funktionell ändring, bara `create or replace` med `search_path = ''`.

create or replace function app_private.log_write_attempt(
    p_key_hash           text,
    p_outcome            text,
    p_risk_check_passed  boolean default null,
    p_tool               text default 'save_workspace_prompt'
)
returns void
language sql
security definer
set search_path = ''
as $$
    insert into app_private.mcp_write_attempts (key_hash, outcome, risk_check_passed, tool)
    values (p_key_hash, p_outcome, p_risk_check_passed, p_tool);
$$;

create or replace function public.log_write_attempt(
    p_key_hash           text,
    p_outcome            text,
    p_risk_check_passed  boolean default null,
    p_tool               text default 'save_workspace_prompt'
)
returns void
language sql
security definer
set search_path = ''
as $$
    select app_private.log_write_attempt(p_key_hash, p_outcome, p_risk_check_passed, p_tool);
$$;

create or replace function app_private.save_my_item_for_key(
    p_key_hash         text,
    p_idempotency_key  uuid,
    p_type             text,
    p_title            text,
    p_content          text,
    p_category         text default null
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key         public.api_keys%rowtype;
    v_ws          public.workspaces%rowtype;
    v_existing    public.content_items%rowtype;
    v_row         public.content_items%rowtype;
    v_recent_attempts integer;
    v_monthly_saves   integer;
    v_slug        text;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    if p_type not in ('prompt', 'assistant') then
        raise exception 'Ogiltig typ.';
    end if;
    if trim(coalesce(p_title, '')) = '' or length(p_title) > 200 then
        raise exception 'Titel måste vara 1–200 tecken.';
    end if;
    if trim(coalesce(p_content, '')) = '' or length(p_content) > 20000 then
        raise exception 'Innehåll måste vara 1–20000 tecken.';
    end if;

    if p_idempotency_key is not null then
        select * into v_existing
          from public.content_items
         where workspace_id = v_ws.id and module = 'valvet' and idempotency_key = p_idempotency_key;
        if found then
            return v_existing;
        end if;
    end if;

    if v_ws.plan = 'free' then
        select count(*) into v_monthly_saves
          from app_private.mcp_write_attempts
         where workspace_id = v_ws.id
           and tool = 'save_my_item'
           and outcome = 'success'
           and created_at >= date_trunc('month', now());
        if v_monthly_saves >= 5 then
            raise exception 'Månadskvoten på 5 nya insättningar via MCP är förbrukad. Skapa via webbappen, eller uppgradera till Pro.';
        end if;
    end if;

    v_slug := app_private.slugify_candidate(p_title, 'valv');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(p_title, 'valv') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility, idempotency_key
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id, p_type::public.content_item_type, 'valvet',
        p_title, v_slug, p_content, p_category, 'draft', 'private', p_idempotency_key
    )
    returning * into v_row;

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, 'save_my_item', 'success');

    return v_row;
end;
$$;

create or replace function app_private.update_my_item_for_key(
    p_key_hash            text,
    p_id                  uuid,
    p_expected_updated_at timestamptz,
    p_title               text default null,
    p_content             text default null,
    p_category            text default null
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key     public.api_keys%rowtype;
    v_ws      public.workspaces%rowtype;
    v_current public.content_items%rowtype;
    v_row     public.content_items%rowtype;
    v_recent_attempts integer;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    if not app_private.has_active_pro_entitlement(v_ws.owner_user_id) then
        raise exception 'Uppgradera till Pro för att uppdatera via MCP.';
    end if;

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    if p_title is not null and (trim(p_title) = '' or length(p_title) > 200) then
        raise exception 'Titel måste vara 1–200 tecken.';
    end if;
    if p_content is not null and (trim(p_content) = '' or length(p_content) > 20000) then
        raise exception 'Innehåll måste vara 1–20000 tecken.';
    end if;

    select * into v_current
      from public.content_items
     where id = p_id and workspace_id = v_ws.id and module = 'valvet' and owner_user_id = v_ws.owner_user_id;
    if not found then
        raise exception 'Insättningen hittades inte.';
    end if;

    if v_current.updated_at <> p_expected_updated_at then
        raise exception 'Insättningen har ändrats sedan du hämtade den — hämta på nytt med get_my_item och försök igen.';
    end if;

    update public.content_items
       set title    = coalesce(p_title, title),
           content  = coalesce(p_content, content),
           category = coalesce(p_category, category)
     where id = p_id
    returning * into v_row;

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, 'update_my_item', 'success');

    return v_row;
end;
$$;

create or replace function app_private.archive_my_item_for_key(
    p_key_hash text,
    p_id       uuid,
    p_confirm  boolean,
    p_restore  boolean default false
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key     public.api_keys%rowtype;
    v_ws      public.workspaces%rowtype;
    v_current public.content_items%rowtype;
    v_row     public.content_items%rowtype;
    v_target_status public.content_status;
    v_recent_attempts integer;
    v_tool text;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then
        raise exception 'Ogiltig nyckel.';
    end if;

    if not app_private.has_active_pro_entitlement(v_ws.owner_user_id) then
        raise exception 'Uppgradera till Pro för att arkivera/återställa via MCP.';
    end if;

    if p_confirm is distinct from true then
        raise exception 'confirm måste vara true för att arkivera eller återställa.';
    end if;

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    select * into v_current
      from public.content_items
     where id = p_id and workspace_id = v_ws.id and module = 'valvet' and owner_user_id = v_ws.owner_user_id;
    if not found then
        raise exception 'Insättningen hittades inte.';
    end if;

    v_target_status := case when p_restore then 'draft' else 'archived' end;
    v_tool := case when p_restore then 'archive_my_item_restore' else 'archive_my_item' end;

    if v_current.status = v_target_status then
        return v_current; -- redan i önskat läge, säker no-op
    end if;

    update public.content_items
       set status = v_target_status
     where id = p_id
    returning * into v_row;

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, v_tool, 'success');

    return v_row;
end;
$$;
