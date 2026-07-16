-- 20260716102500_valvet_update_archive_rpc.sql

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
set search_path = public, app_private, pg_temp
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

revoke all on function app_private.update_my_item_for_key(text, uuid, timestamptz, text, text, text) from public;

create or replace function public.update_my_item_for_key(
    p_key_hash text, p_id uuid, p_expected_updated_at timestamptz,
    p_title text default null, p_content text default null, p_category text default null
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.update_my_item_for_key(p_key_hash, p_id, p_expected_updated_at, p_title, p_content, p_category);
$$;

revoke all on function public.update_my_item_for_key(text, uuid, timestamptz, text, text, text) from public;
grant execute on function public.update_my_item_for_key(text, uuid, timestamptz, text, text, text) to anon, authenticated;


create or replace function app_private.archive_my_item_for_key(
    p_key_hash text,
    p_id       uuid,
    p_confirm  boolean,
    p_restore  boolean default false
)
returns public.content_items
language plpgsql
security definer
set search_path = public, app_private, pg_temp
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

revoke all on function app_private.archive_my_item_for_key(text, uuid, boolean, boolean) from public;

create or replace function public.archive_my_item_for_key(
    p_key_hash text, p_id uuid, p_confirm boolean, p_restore boolean default false
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.archive_my_item_for_key(p_key_hash, p_id, p_confirm, p_restore);
$$;

revoke all on function public.archive_my_item_for_key(text, uuid, boolean, boolean) from public;
grant execute on function public.archive_my_item_for_key(text, uuid, boolean, boolean) to anon, authenticated;
