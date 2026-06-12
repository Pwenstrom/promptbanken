-- Promptbanken MVP read views for API/MCP.
-- Review before running: views use security_invoker so underlying RLS still applies on Postgres 15+.

create or replace view public.published_public_content
with (security_invoker = true)
as
select
    ci.id,
    ci.workspace_id,
    ci.type,
    ci.title,
    ci.slug,
    ci.summary,
    ci.content,
    ci.category,
    ci.audience,
    ci.published_at,
    ci.updated_at
from public.content_items ci
where ci.status = 'published'
  and ci.visibility = 'public';

create or replace view public.published_workspace_content
with (security_invoker = true)
as
select
    ci.id,
    ci.workspace_id,
    ci.type,
    ci.title,
    ci.slug,
    ci.summary,
    ci.content,
    ci.visibility,
    ci.category,
    ci.audience,
    ci.published_at,
    ci.updated_at
from public.content_items ci
where ci.status = 'published'
  and ci.visibility in ('workspace', 'public');

grant select on public.published_public_content to anon, authenticated;
grant select on public.published_workspace_content to authenticated;

comment on view public.published_public_content is
    'Read-only API/MCP surface for public published Promptbanken content. Uses security_invoker and underlying RLS.';

comment on view public.published_workspace_content is
    'Read-only workspace-authenticated API/MCP surface for published Promptbanken content. Uses security_invoker and underlying RLS.';
