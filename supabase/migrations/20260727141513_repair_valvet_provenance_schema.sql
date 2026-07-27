-- Repair for 20260720120000, which was present in remote migration history
-- without its schema objects being present in the linked production project.
-- Etapp 1-uppföljning: hållbar källspårning för mallkopior och validerade
-- paket-id:n i både webb-CRUD och MCP-RPC:er.

alter table public.content_items
    add column if not exists source_template_id uuid,
    add column if not exists source_version text,
    add column if not exists source_copied_at timestamptz;

comment on column public.content_items.source_template_id is
    'Källmall i pro_prompt_templates när ett Valvet-objekt skapats via copy_template_to_valvet.';
comment on column public.content_items.source_version is
    'Deterministisk versionshash av källmallens innehåll vid kopieringstillfället.';
comment on column public.content_items.source_copied_at is
    'Tidpunkt då en pro_prompt_template kopierades till Valvet.';

create or replace function app_private.pro_prompt_template_source_version(
    p_template public.pro_prompt_templates
)
returns text
language sql
immutable
set search_path = ''
as $$
    select encode(
        extensions.digest(
            jsonb_build_object(
                'area', p_template.area,
                'area_label', p_template.area_label,
                'title', p_template.title,
                'syfte', p_template.syfte,
                'output_format', p_template.output_format,
                'prompt_text', p_template.prompt_text,
                'tags', p_template.tags,
                'risk_level', p_template.risk_level,
                'security_examples', p_template.security_examples,
                'sort_order', p_template.sort_order
            )::text,
            'sha256'
        ),
        'hex'
    );
$$;

revoke all on function app_private.pro_prompt_template_source_version(public.pro_prompt_templates) from public;

with historical_template_items as (
    select
        ci.id,
        ci.workspace_id,
        row_number() over (
            partition by ci.workspace_id
            order by ci.updated_at, ci.id
        ) as copy_seq
      from public.content_items ci
     where ci.module = 'valvet'
       and ci.source = 'catalog_copy'
       and ci.type = 'prompt'
       and ci.source_content_item_id is null
       and ci.source_template_id is null
), historical_template_logs as (
    select
        l.workspace_id,
        l.source_content_item_id as template_id,
        l.created_at,
        row_number() over (
            partition by l.workspace_id
            order by l.created_at, l.id
        ) as copy_seq
      from app_private.valvet_catalog_copies l
      join public.pro_prompt_templates t on t.id = l.source_content_item_id
)
update public.content_items ci
   set source_template_id = logs.template_id,
       source_version = app_private.pro_prompt_template_source_version(t),
       source_copied_at = logs.created_at
  from historical_template_items items
  join historical_template_logs logs
    on logs.workspace_id = items.workspace_id
   and logs.copy_seq = items.copy_seq
  join public.pro_prompt_templates t
    on t.id = logs.template_id
 where ci.id = items.id;

create or replace function app_private.prompt_package_area_exists(p_area text)
returns boolean
language sql
stable
set search_path = ''
as $$
    select exists (
        select 1
          from public.pro_prompt_templates t
         where t.area = btrim(p_area)
    );
$$;

revoke all on function app_private.prompt_package_area_exists(text) from public;

create or replace function app_private.enforce_known_prompt_package_area()
returns trigger
language plpgsql
set search_path = public, app_private, pg_temp
as $$
begin
    new.area := btrim(new.area);
    if new.area is null or new.area = '' then
        raise exception 'Paket-id måste anges.';
    end if;
    if not app_private.prompt_package_area_exists(new.area) then
        raise exception 'Okänt paket-id.';
    end if;
    return new;
end;
$$;

revoke all on function app_private.enforce_known_prompt_package_area() from public;

drop trigger if exists enforce_known_prompt_package_area on public.valvet_package_activations;
create trigger enforce_known_prompt_package_area
before insert or update of area on public.valvet_package_activations
for each row execute function app_private.enforce_known_prompt_package_area();

create or replace function app_private.copy_template_to_valvet(
    p_template_id uuid
)
returns public.content_items
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_ws             public.workspaces%rowtype;
    v_source         public.pro_prompt_templates%rowtype;
    v_row            public.content_items%rowtype;
    v_copy_count     integer;
    v_slug           text;
    v_is_pro         boolean;
    v_source_version text;
    v_copied_at      timestamptz := now();
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
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

    v_is_pro := app_private.has_active_pro_entitlement(v_ws.owner_user_id);

    select * into v_source
      from public.pro_prompt_templates
     where id = p_template_id;

    if not found then
        raise exception 'Den här mallen finns inte.';
    end if;

    v_source_version := app_private.pro_prompt_template_source_version(v_source);

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
        content, category, status, visibility, source, source_content_item_id,
        source_template_id, source_version, source_copied_at
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id,
        'prompt'::public.content_item_type, 'valvet',
        v_source.title, v_slug, v_source.prompt_text, v_source.area_label,
        'draft', 'private', 'catalog_copy', null,
        v_source.id, v_source_version, v_copied_at
    )
    returning * into v_row;

    insert into app_private.valvet_catalog_copies (workspace_id, source_content_item_id)
    values (v_ws.id, p_template_id);

    return v_row;
end;
$$;

revoke all on function app_private.copy_template_to_valvet(uuid) from public;

create or replace function public.copy_template_to_valvet(p_template_id uuid)
returns public.content_items
language sql
security definer
set search_path = ''
as $$
    select * from app_private.copy_template_to_valvet(p_template_id);
$$;

revoke all on function public.copy_template_to_valvet(uuid) from public;
grant execute on function public.copy_template_to_valvet(uuid) to authenticated;

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
    v_source_version  text;
    v_copied_at       timestamptz := now();
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

    v_source_version := app_private.pro_prompt_template_source_version(v_source);

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
        content, category, status, visibility, source, source_content_item_id,
        source_template_id, source_version, source_copied_at
    ) values (
        v_ws.id, v_ws.owner_user_id, v_ws.owner_user_id,
        'prompt'::public.content_item_type, 'valvet',
        v_source.title, v_slug, v_source.prompt_text, v_source.area_label,
        'draft', 'private', 'catalog_copy', null,
        v_source.id, v_source_version, v_copied_at
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
    v_key  public.api_keys%rowtype;
    v_ws   public.workspaces%rowtype;
    v_area text;
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

    v_area := btrim(p_area);
    if v_area is null or v_area = '' then
        raise exception 'Paket-id måste anges.';
    end if;
    if not app_private.prompt_package_area_exists(v_area) then
        raise exception 'Okänt paket-id.';
    end if;

    insert into public.valvet_package_activations (workspace_id, area)
    values (v_ws.id, v_area)
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

    return query
    select a.area
      from public.valvet_package_activations a
     where a.workspace_id = v_ws.id
       and app_private.prompt_package_area_exists(a.area)
     order by a.area;
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
