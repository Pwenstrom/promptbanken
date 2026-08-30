-- 20260831110500_create_creator_share_gen_random_bytes_fix.sql
-- Fixup för 20260831110000_creator_shares_private_content.sql, men fångar
-- en ÄLDRE pre-existing bugg: create_creator_share (20260825090000) anropade
-- gen_random_bytes(16) helt okvalificerat, trots `set search_path = ''`.
-- pgcrypto är installerat i schemat `extensions`
-- (20260612120000_initial_schema.sql: "create extension if not exists
-- pgcrypto with schema extensions"), så anropet måste vara
-- extensions.gen_random_bytes(16). Utan detta har create_creator_share
-- ALDRIG kunnat skapa en delning i produktion -- varje anrop, för både
-- publicerat och (nu) opublicerat innehåll, misslyckas med
-- "function gen_random_bytes(integer) does not exist". Fångat av
-- supabase/tests/verify_creator_shares_private_content.sql innan merge.
--
-- Detta är samma create_creator_share som redan skrevs om i
-- 20260831110000 för fyra subject_type-värden -- den migrationen har
-- redan rättats till att använda extensions.gen_random_bytes, så den här
-- filen behövs bara för att repot ska ha en tydlig, separat post i
-- historiken om felet (och för att skydda mot att migrationen
-- appliceras i en annan ordning senare). Definitionen nedan är identisk
-- med den som redan gäller efter 20260831110000.

create or replace function app_private.create_creator_share(
    p_subject_type text,
    p_subject_id uuid,
    p_pin_version boolean default false,
    p_expires_at timestamptz default null,
    p_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := (select auth.uid());
    v_profile_id uuid;
    v_owns boolean;
    v_payload jsonb;
    v_snapshot_id uuid;
    v_token text := encode(extensions.gen_random_bytes(16), 'hex');
    v_share_id uuid;
begin
    if v_user is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    if p_subject_type not in ('prompt', 'package', 'draft_prompt', 'package_draft') then
        raise exception 'Okänd typ: %.', p_subject_type;
    end if;

    select id into v_profile_id from public.creator_profiles where user_id = v_user;
    if v_profile_id is null then
        raise exception 'Du behöver en creator-profil för att kunna dela innehåll.';
    end if;

    if p_subject_type = 'prompt' then
        select exists (
            select 1 from public.catalog_prompts
             where id = p_subject_id and status = 'published' and creator_profile_id = v_profile_id
        ) into v_owns;
    elsif p_subject_type = 'package' then
        select exists (
            select 1 from public.catalog_packages
             where id = p_subject_id and status = 'published' and creator_profile_id = v_profile_id
        ) into v_owns;
    elsif p_subject_type = 'draft_prompt' then
        select exists (
            select 1 from public.content_items
             where id = p_subject_id and owner_user_id = v_user and module = 'kommun' and type = 'prompt'
        ) into v_owns;
    else -- package_draft
        select exists (
            select 1 from public.creator_package_drafts
             where id = p_subject_id and owner_user_id = v_user
        ) into v_owns;
    end if;

    if not v_owns then
        raise exception 'Du kan bara dela ditt eget innehåll.';
    end if;

    if coalesce(p_pin_version, false) then
        v_payload := app_private.build_content_payload(p_subject_type, p_subject_id);
        if v_payload is null then
            raise exception 'Innehållet kunde inte läsas för låsning.';
        end if;
        insert into public.content_snapshots (subject_type, subject_id, payload)
        values (p_subject_type, p_subject_id, v_payload)
        returning id into v_snapshot_id;
    end if;

    insert into public.creator_shares (
        owner_user_id, subject_type, subject_id, token, snapshot_id, label, expires_at
    )
    values (
        v_user, p_subject_type, p_subject_id, v_token, v_snapshot_id,
        nullif(trim(coalesce(p_label, '')), ''), p_expires_at
    )
    returning id into v_share_id;

    return jsonb_build_object('id', v_share_id, 'token', v_token, 'pinned', v_snapshot_id is not null);
end;
$$;
