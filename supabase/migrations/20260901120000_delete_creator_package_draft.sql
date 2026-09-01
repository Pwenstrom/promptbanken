-- creator_package_drafts har medvetet ingen delete-policy (se kommentar i
-- 20260821200411_creator_authoring.sql: "allt går via RPC:erna nedan").
-- Prompter (content_items) fick en riktig delete-policy 2026-06-30
-- (content_items_owners_delete_non_published), men paket saknade
-- motsvarande väg helt -- varken RPC eller policy. En ägare kunde skapa
-- ett paketutkast men aldrig ta bort det.
--
-- Samma gräns som withdraw_creator_package_draft: bara draft/review.
-- Publicerade paket tas inte bort härifrån (måste avpubliceras av admin
-- först, samma princip som för prompter).

create or replace function app_private.delete_creator_package_draft(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_deleted_id uuid;
begin
    delete from public.creator_package_drafts
     where id = p_draft_id
       and owner_user_id = (select auth.uid())
       and status in ('draft', 'review')
    returning id into v_deleted_id;

    if v_deleted_id is null then
        raise exception 'Paketet hittades inte, tillhör inte dig, eller är publicerat (publicerade paket måste avpubliceras innan de kan tas bort).';
    end if;

    return jsonb_build_object('id', v_deleted_id);
end;
$$;

revoke all on function app_private.delete_creator_package_draft(uuid) from public;

create or replace function public.delete_creator_package_draft(p_draft_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.delete_creator_package_draft(p_draft_id);
$$;

revoke all on function public.delete_creator_package_draft(uuid) from public;
grant execute on function public.delete_creator_package_draft(uuid) to authenticated;
