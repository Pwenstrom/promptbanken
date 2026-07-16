-- 20260716102000_valvet_save_rpc.sql

-- Bredda den befintliga log_write_attempt (byggd för save_workspace_prompt,
-- 20260712110000) med en valfri p_tool-parameter. create or replace på en
-- funktion med ENDAST tillagda parametrar med default-värden är
-- bakåtkompatibelt -- befintliga 3-parameters-anrop matchar fortfarande
-- och får tool='save_workspace_prompt' automatiskt.
create or replace function app_private.log_write_attempt(
    p_key_hash           text,
    p_outcome            text,
    p_risk_check_passed  boolean default null,
    p_tool               text default 'save_workspace_prompt'
)
returns void
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    insert into app_private.mcp_write_attempts (key_hash, outcome, risk_check_passed, tool)
    values (p_key_hash, p_outcome, p_risk_check_passed, p_tool);
$$;

revoke all on function app_private.log_write_attempt(text, text, boolean, text) from public;
grant execute on function app_private.log_write_attempt(text, text, boolean, text) to anon;

create or replace function public.log_write_attempt(
    p_key_hash           text,
    p_outcome            text,
    p_risk_check_passed  boolean default null,
    p_tool               text default 'save_workspace_prompt'
)
returns void
language sql
security definer
set search_path = public, app_private, pg_temp
as $$
    select app_private.log_write_attempt(p_key_hash, p_outcome, p_risk_check_passed, p_tool);
$$;

revoke all on function public.log_write_attempt(text, text, boolean, text) from public;
grant execute on function public.log_write_attempt(text, text, boolean, text) to anon;


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
set search_path = public, app_private, pg_temp
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

revoke all on function app_private.save_my_item_for_key(text, uuid, text, text, text, text) from public;

create or replace function public.save_my_item_for_key(
    p_key_hash text, p_idempotency_key uuid, p_type text, p_title text, p_content text, p_category text default null
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.save_my_item_for_key(p_key_hash, p_idempotency_key, p_type, p_title, p_content, p_category);
$$;

revoke all on function public.save_my_item_for_key(text, uuid, text, text, text, text) from public;
grant execute on function public.save_my_item_for_key(text, uuid, text, text, text, text) to anon, authenticated;
