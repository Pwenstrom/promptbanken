-- 20260716101500_valvet_read_rpcs.sql

create or replace function app_private.list_my_items_for_key(
    p_key_hash text,
    p_type     text default null,
    p_category text default null,
    p_status   text default null
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then return; end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then return; end if;

    return query
    select ci.id, ci.type::text, ci.title, ci.content, ci.category, ci.status::text, ci.updated_at
      from public.content_items ci
     where ci.workspace_id = v_ws.id
       and ci.module = 'valvet'
       and ci.owner_user_id = v_ws.owner_user_id
       and (
           (p_status is not null and ci.status::text = p_status)
           or (p_status is null and ci.status <> 'archived')
       )
       and (p_type is null or ci.type::text = p_type)
       and (p_category is null or ci.category = p_category)
     order by ci.updated_at desc;
end;
$$;

revoke all on function app_private.list_my_items_for_key(text, text, text, text) from public;

create or replace function public.list_my_items_for_key(
    p_key_hash text, p_type text default null, p_category text default null, p_status text default null
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.list_my_items_for_key(p_key_hash, p_type, p_category, p_status);
$$;

revoke all on function public.list_my_items_for_key(text, text, text, text) from public;
grant execute on function public.list_my_items_for_key(text, text, text, text) to anon, authenticated;


create or replace function app_private.search_my_items_for_key(
    p_key_hash text,
    p_query    text,
    p_type     text default null,
    p_category text default null
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
begin
    if coalesce(trim(p_query), '') = '' then
        return;
    end if;

    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then return; end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then return; end if;

    return query
    select ci.id, ci.type::text, ci.title, ci.content, ci.category, ci.status::text, ci.updated_at
      from public.content_items ci
     where ci.workspace_id = v_ws.id
       and ci.module = 'valvet'
       and ci.owner_user_id = v_ws.owner_user_id
       and ci.status <> 'archived'
       and (p_type is null or ci.type::text = p_type)
       and (p_category is null or ci.category = p_category)
       and (
           ci.title ilike '%' || p_query || '%'
           or ci.content ilike '%' || p_query || '%'
           or coalesce(ci.category, '') ilike '%' || p_query || '%'
       )
     order by ci.updated_at desc;
end;
$$;

revoke all on function app_private.search_my_items_for_key(text, text, text, text) from public;

create or replace function public.search_my_items_for_key(
    p_key_hash text, p_query text, p_type text default null, p_category text default null
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.search_my_items_for_key(p_key_hash, p_query, p_type, p_category);
$$;

revoke all on function public.search_my_items_for_key(text, text, text, text) from public;
grant execute on function public.search_my_items_for_key(text, text, text, text) to anon, authenticated;


create or replace function app_private.get_my_item_for_key(
    p_key_hash text,
    p_id       uuid
)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
begin
    select k.* into v_key from public.api_keys k
     where k.key_hash = p_key_hash and k.revoked_at is null and k.scopes @> array['mcp']::text[]
     limit 1;
    if not found then return; end if;

    select w.* into v_ws from public.workspaces w
     where w.id = v_key.workspace_id and w.mcp_enabled = true and w.status = 'active';
    if not found then return; end if;

    return query
    select ci.id, ci.type::text, ci.title, ci.content, ci.category, ci.status::text, ci.updated_at
      from public.content_items ci
     where ci.id = p_id
       and ci.workspace_id = v_ws.id
       and ci.module = 'valvet'
       and ci.owner_user_id = v_ws.owner_user_id;
end;
$$;

revoke all on function app_private.get_my_item_for_key(text, uuid) from public;

create or replace function public.get_my_item_for_key(p_key_hash text, p_id uuid)
returns table(
    id uuid, type text, title text, content text, category text,
    status text, updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.get_my_item_for_key(p_key_hash, p_id);
$$;

revoke all on function public.get_my_item_for_key(text, uuid) from public;
grant execute on function public.get_my_item_for_key(text, uuid) to anon, authenticated;
