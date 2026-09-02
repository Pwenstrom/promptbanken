-- supabase/tests/verify_creator_delete_operations.sql
-- Self-contained, rollback-wrapped. Verifierar borttagning i Creator:
-- egna prompts, egna paket-utkast, följda katalogreferenser, samt att
-- publicerat/under granskning och främmande ägare vägras.
--
-- Kör hela filen och läs resultattabellen sist: varje rad är ett påstående
-- med ok=true/false och en detaljsträng som visar vad som faktiskt hände.

begin;

create temp table del_results (
  test text primary key,
  ok boolean not null,
  detail text not null
);

grant select, insert, update, delete on table del_results to anon, authenticated;

-- Fixturer -----------------------------------------------------------------

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('b0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'del.owner@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'del.stranger@example.test', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.workspaces (id, name, slug, type, plan, owner_user_id, max_prompts, mcp_enabled)
values ('b1000000-0000-0000-0000-000000000001', 'Del ws', 'del-ws', 'personal', 'pro', 'b0000000-0000-0000-0000-000000000001', 100, true);

insert into public.profiles (user_id, workspace_id, role)
values ('b0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'editor');

-- JWT-claimen måste sättas redan här: triggern
-- app_private.enforce_content_access_model kräver created_by = auth.uid()
-- på varje prompt-insert, även när fixturen läggs in som superuser.
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);

-- Egna prompts i tre lägen: utkast, under granskning, publicerad.
insert into public.content_items (id, workspace_id, owner_user_id, created_by, type, module, title, slug, content, status, visibility)
values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'prompt', 'kommun', 'Eget utkast', 'del-draft', 'Text', 'draft', 'private'),
  ('b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'prompt', 'kommun', 'Under granskning', 'del-review', 'Text', 'review', 'private'),
  ('b2000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'prompt', 'kommun', 'Publicerad', 'del-published', 'Text', 'published', 'private'),
  ('b2000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'prompt', 'kommun', 'Delad prompt', 'del-shared', 'Text', 'draft', 'private');

-- En aktiv delningslänk mot utkastet som ska raderas.
insert into public.creator_shares (id, owner_user_id, subject_type, subject_id, token)
values ('b3000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'prompt', 'b2000000-0000-0000-0000-000000000004', 'del-share-token-1');

-- Katalogfixturer för referensvägen.
insert into public.catalog_prompts (id, slug, status)
values ('b4000000-0000-0000-0000-000000000001', 'del-fixture-prompt', 'published');
insert into public.catalog_prompt_variants (prompt_id, context_key, title, summary, prompt_text, area)
values ('b4000000-0000-0000-0000-000000000001', 'generell', 'Katalogprompt live', 'Live-sammanfattning', 'Prompttext', 'Skriva');

insert into public.catalog_packages (id, slug, status, package_type)
values ('b5000000-0000-0000-0000-000000000001', 'del-fixture-package', 'published', 'collection');
insert into public.catalog_package_variants (package_id, context_key, title, summary, intro_text)
values ('b5000000-0000-0000-0000-000000000001', 'generell', 'Katalogpaket', 'Paketsammanfattning', 'Intro');
insert into public.catalog_package_items (package_id, prompt_id, sort_order)
values ('b5000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 0);

-- Ett publicerat paket-utkast, som inte får tas bort härifrån.
insert into public.creator_package_drafts (id, owner_user_id, title, summary, status)
values ('b6000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Publicerat paket', 'Sammanfattning', 'published');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);

-- 1. Egna prompts ----------------------------------------------------------

do $$
declare
    v_result jsonb;
    v_left   integer;
begin
    v_result := public.delete_my_creator_prompt('b2000000-0000-0000-0000-000000000001');
    select count(*) into v_left from public.content_items where id = 'b2000000-0000-0000-0000-000000000001';

    insert into del_results values (
        '1a - egen utkastprompt raderas',
        v_left = 0 and (v_result->>'deleted')::boolean,
        'rows_left=' || v_left || ' result=' || v_result::text
    );
end $$;

do $$
declare
    v_msg text := '<inget fel>';
    v_left integer;
begin
    begin
        perform public.delete_my_creator_prompt('b2000000-0000-0000-0000-000000000003');
    exception when others then
        v_msg := sqlerrm;
    end;

    select count(*) into v_left from public.content_items where id = 'b2000000-0000-0000-0000-000000000003';
    insert into del_results values (
        '1b - publicerad prompt vagras',
        v_left = 1 and v_msg like 'Publicerade prompts%',
        'rows_left=' || v_left || ' error=' || v_msg
    );
end $$;

do $$
declare
    v_msg text := '<inget fel>';
    v_left integer;
begin
    begin
        perform public.delete_my_creator_prompt('b2000000-0000-0000-0000-000000000002');
    exception when others then
        v_msg := sqlerrm;
    end;

    select count(*) into v_left from public.content_items where id = 'b2000000-0000-0000-0000-000000000002';
    insert into del_results values (
        '1c - prompt under granskning vagras',
        v_left = 1 and v_msg like '%under granskning%',
        'rows_left=' || v_left || ' error=' || v_msg
    );
end $$;

-- Raderas här, granskas efter reset role: creator_shares har ingen
-- SELECT-grant till authenticated (allt läsande går via RPC), så
-- kontrollen av revoked_at ligger i blocket längst ned.
do $$
begin
    perform public.delete_my_creator_prompt('b2000000-0000-0000-0000-000000000004');
end $$;

-- 2. Foljda katalogprompts -------------------------------------------------

do $$
declare
    v_ref       public.content_items;
    v_listed    record;
    v_result    jsonb;
    v_left      integer;
    v_list_ok   boolean := false;
begin
    v_ref := public.add_catalog_prompt_to_library('b4000000-0000-0000-0000-000000000001');

    select * into v_listed
      from public.list_my_library_prompts()
     where id = v_ref.id;

    v_list_ok := found
        and v_listed.is_library_reference
        and v_listed.title = 'Katalogprompt live'
        and v_listed.source_prompt_id = 'b4000000-0000-0000-0000-000000000001';

    insert into del_results values (
        '2a - foljd prompt syns i list_my_library_prompts med live-titel',
        v_list_ok,
        'title=' || coalesce(v_listed.title, '<ingen rad>') ||
        ' is_ref=' || coalesce(v_listed.is_library_reference::text, '<null>')
    );

    v_result := public.delete_my_creator_prompt(v_ref.id);
    select count(*) into v_left from public.content_items where id = v_ref.id;

    insert into del_results values (
        '2b - foljd prompt gar att sluta folja',
        v_left = 0 and (v_result->>'was_library_reference')::boolean,
        'rows_left=' || v_left || ' result=' || v_result::text
    );
end $$;

-- 3. Paket -----------------------------------------------------------------

do $$
declare
    v_draft_id  uuid;
    v_prompt    public.content_items;
    v_items     integer;
    v_left      integer;
begin
    perform public.upsert_creator_package_draft(null, 'Eget paket', 'Sammanfattning', 'collection');
    select id into v_draft_id
      from public.creator_package_drafts
     where owner_user_id = 'b0000000-0000-0000-0000-000000000001'
       and title = 'Eget paket';

    v_prompt := public.copy_published_prompt_to_valvet('b4000000-0000-0000-0000-000000000001');
    perform public.add_prompt_to_package_draft(v_draft_id, v_prompt.id, 0);

    perform public.delete_my_creator_package_draft(v_draft_id);

    select count(*) into v_left from public.creator_package_drafts where id = v_draft_id;
    select count(*) into v_items from public.creator_package_items where draft_id = v_draft_id;

    insert into del_results values (
        '3a - eget paket-utkast raderas och items faller bort',
        v_left = 0 and v_items = 0,
        'drafts_left=' || v_left || ' items_left=' || v_items
    );
end $$;

do $$
declare
    v_draft   public.creator_package_drafts;
    v_listed  record;
    v_result  jsonb;
    v_left    integer;
    v_flag_ok boolean := false;
begin
    v_draft := public.add_catalog_package_to_library('b5000000-0000-0000-0000-000000000001');

    select * into v_listed
      from public.list_my_creator_package_drafts()
     where id = v_draft.id;
    v_flag_ok := found and v_listed.is_library_reference;

    insert into del_results values (
        '3b - paketreferens flaggas som referens i listan',
        v_flag_ok,
        'is_ref=' || coalesce(v_listed.is_library_reference::text, '<ingen rad>')
    );

    v_result := public.delete_my_creator_package_draft(v_draft.id);
    select count(*) into v_left from public.creator_package_drafts where id = v_draft.id;

    insert into del_results values (
        '3c - foljt paket gar att sluta folja',
        v_left = 0 and (v_result->>'was_library_reference')::boolean,
        'rows_left=' || v_left || ' result=' || v_result::text
    );
end $$;

do $$
declare
    v_msg  text := '<inget fel>';
    v_left integer;
begin
    begin
        perform public.delete_my_creator_package_draft('b6000000-0000-0000-0000-000000000001');
    exception when others then
        v_msg := sqlerrm;
    end;

    select count(*) into v_left from public.creator_package_drafts where id = 'b6000000-0000-0000-0000-000000000001';
    insert into del_results values (
        '3d - publicerat paket vagras',
        v_left = 1 and v_msg like 'Publicerade paket%',
        'rows_left=' || v_left || ' error=' || v_msg
    );
end $$;

-- 4. Agarskap --------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);

do $$
declare
    v_msg  text := '<inget fel>';
begin
    begin
        perform public.delete_my_creator_prompt('b2000000-0000-0000-0000-000000000002');
    exception when others then
        v_msg := sqlerrm;
    end;

    insert into del_results values (
        '4a - annan anvandare vagras',
        v_msg like '%tillhör inte dig%',
        'error=' || v_msg
    );
end $$;

reset role;

-- Radräkningen görs som superuser: en främmande användare ser inte
-- ägarens privata prompt genom RLS, så ett count(*) i blocket ovan hade
-- blivit 0 oavsett om raden fanns kvar eller inte.
do $$
declare
    v_left integer;
begin
    select count(*) into v_left from public.content_items where id = 'b2000000-0000-0000-0000-000000000002';
    insert into del_results values (
        '4b - prompten finns kvar efter frammande raderingsforsok',
        v_left = 1,
        'rows_left=' || v_left
    );
end $$;

do $$
declare
    v_revoked timestamptz;
begin
    select revoked_at into v_revoked
      from public.creator_shares
     where id = 'b3000000-0000-0000-0000-000000000001';

    insert into del_results values (
        '1d - aktiv delning avslutas nar prompten raderas',
        v_revoked is not null,
        'revoked_at=' || coalesce(v_revoked::text, '<null>')
    );
end $$;

select test, ok, detail from del_results order by test;

rollback;
