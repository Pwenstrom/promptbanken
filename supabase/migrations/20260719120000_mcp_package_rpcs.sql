-- 20260719120000_mcp_package_rpcs.sql
-- Delprojekt 4: MCP-exponering av promptpaket. Fyra nyckelhash-baserade
-- RPC:er, samma mönster som save_my_item_for_key/archive_my_item_for_key
-- (20260716102000/20260716102500). Se
-- docs/superpowers/specs/2026-07-19-mcp-paket-exponering-design.md

create or replace function app_private.copy_template_to_valvet_for_key(
    p_key_hash    text,
    p_template_id uuid,
    p_confirm     boolean
)
returns public.content_items
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key             public.api_keys%rowtype;
    v_ws              public.workspaces%rowtype;
    v_source          public.pro_prompt_templates%rowtype;
    v_row             public.content_items%rowtype;
    v_recent_attempts integer;
    v_copy_count      integer;
    v_slug            text;
    v_is_pro          boolean;
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

    if p_confirm is distinct from true then
        raise exception 'confirm måste vara true för att kopiera en mall.';
    end if;

    select count(*) into v_recent_attempts
      from app_private.mcp_write_attempts
     where key_hash = p_key_hash and created_at >= now() - interval '60 seconds';
    if v_recent_attempts >= 20 then
        raise exception 'För många försök, vänta en minut och försök igen.';
    end if;

    v_is_pro := app_private.has_active_pro_entitlement(v_ws.owner_user_id);

    select * into v_source from public.pro_prompt_templates where id = p_template_id;
    if not found then
        raise exception 'Den här mallen finns inte.';
    end if;

    if not v_is_pro then
        select count(*) into v_copy_count
          from app_private.valvet_catalog_copies
         where workspace_id = v_ws.id
           and created_at >= date_trunc('month', now());
        if v_copy_count >= 5 then
            raise exception 'Månadskvoten på 5 kopior är förbrukad. Uppgradera till Pro för obegränsad kopiering.';
        end if;
    end if;

    v_slug := app_private.slugify_candidate(v_source.title, 'valv');
    while exists (select 1 from public.content_items where workspace_id = v_ws.id and slug = v_slug) loop
        v_slug := app_private.slugify_candidate(v_source.title, 'valv') || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    end loop;

    perform set_config('request.jwt.claim.sub', v_ws.owner_user_id::text, true);

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, module, title, slug,
        content, category, status, visibility, source, source_content_item_id
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id,
        'prompt'::public.content_item_type, 'valvet',
        v_source.title, v_slug, v_source.prompt_text, v_source.area_label,
        'draft', 'private', 'catalog_copy', null
    )
    returning * into v_row;

    insert into app_private.valvet_catalog_copies (workspace_id, source_content_item_id)
    values (v_ws.id, p_template_id);

    insert into app_private.mcp_write_attempts (key_hash, workspace_id, tool, outcome)
    values (p_key_hash, v_ws.id, 'copy_template_to_valvet', 'success');

    return v_row;
end;
$$;

revoke all on function app_private.copy_template_to_valvet_for_key(text, uuid, boolean) from public;

create or replace function public.copy_template_to_valvet_for_key(
    p_key_hash text, p_template_id uuid, p_confirm boolean
)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.copy_template_to_valvet_for_key(p_key_hash, p_template_id, p_confirm);
$$;

revoke all on function public.copy_template_to_valvet_for_key(text, uuid, boolean) from public;
grant execute on function public.copy_template_to_valvet_for_key(text, uuid, boolean) to anon;


-- Aktivera/avaktivera/lista: rör ALDRIG mcp_write_attempts (varken
-- rate-limit-check eller loggning) -- ren UI-konfiguration, inte en
-- skriv-handling som ska räknas mot delad rate limit.
create or replace function app_private.activate_package_for_key(
    p_key_hash text,
    p_area     text
)
returns void
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
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

    insert into public.valvet_package_activations (workspace_id, area)
    values (v_ws.id, p_area)
    on conflict (workspace_id, area) do nothing;
end;
$$;

revoke all on function app_private.activate_package_for_key(text, text) from public;

create or replace function public.activate_package_for_key(p_key_hash text, p_area text)
returns void
language sql
security definer
set search_path = ''
as $$
    select app_private.activate_package_for_key(p_key_hash, p_area);
$$;

revoke all on function public.activate_package_for_key(text, text) from public;
grant execute on function public.activate_package_for_key(text, text) to anon;


create or replace function app_private.deactivate_package_for_key(
    p_key_hash text,
    p_area     text
)
returns void
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
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

    delete from public.valvet_package_activations
     where workspace_id = v_ws.id and area = p_area;
end;
$$;

revoke all on function app_private.deactivate_package_for_key(text, text) from public;

create or replace function public.deactivate_package_for_key(p_key_hash text, p_area text)
returns void
language sql
security definer
set search_path = ''
as $$
    select app_private.deactivate_package_for_key(p_key_hash, p_area);
$$;

revoke all on function public.deactivate_package_for_key(text, text) from public;
grant execute on function public.deactivate_package_for_key(text, text) to anon;


create or replace function app_private.list_active_packages_for_key(p_key_hash text)
returns table(area text)
language plpgsql
security definer
set search_path = public, app_private, pg_temp
as $$
declare
    v_key public.api_keys%rowtype;
    v_ws  public.workspaces%rowtype;
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

    return query select a.area from public.valvet_package_activations a where a.workspace_id = v_ws.id;
end;
$$;

revoke all on function app_private.list_active_packages_for_key(text) from public;

create or replace function public.list_active_packages_for_key(p_key_hash text)
returns table(area text)
language sql
security definer
set search_path = ''
as $$
    select * from app_private.list_active_packages_for_key(p_key_hash);
$$;

revoke all on function public.list_active_packages_for_key(text) from public;
grant execute on function public.list_active_packages_for_key(text) to anon;
