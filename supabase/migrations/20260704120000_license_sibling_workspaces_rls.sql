-- Den nya "Arbetsytor"-vyn listar alla arbetsytor under en licens
-- (relevant för Förvaltning/Kommun som kan ha flera). Befintlig RLS
-- (workspaces_members_read) tillät bara att se en arbetsyta man
-- själv skapat (owner_user_id) eller redan är medlem i -- inte
-- syskon-arbetsytor som en kollega skapat under samma licens.
--
-- Ny policy: vem som helst som är medlem i NÅGON arbetsyta under en
-- licens får se ALLA arbetsytor under samma licens (bara metadata --
-- namn/typ/plan, inte innehåll; innehållsläsning styrs fortfarande av
-- content_items egna RLS-policyer per arbetsyta).

drop policy if exists "workspaces_license_siblings_read" on public.workspaces;
create policy "workspaces_license_siblings_read"
on public.workspaces
for select
to authenticated
using (
    license_id is not null
    and license_id in (
        select w2.license_id
          from public.workspaces w2
          join public.profiles p on p.workspace_id = w2.id
         where p.user_id = (select auth.uid())
           and w2.license_id is not null
    )
);
