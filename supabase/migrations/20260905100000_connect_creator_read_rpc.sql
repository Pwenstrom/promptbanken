-- Connect reads one prompt at a time through the caller's auth.uid().
-- The narrow RPC avoids returning every prompt body when Connect only needs one.

create or replace function public.get_my_connect_library_prompt(
    p_content_item_id uuid
)
returns table (
    id uuid,
    title text,
    slug text,
    summary text,
    content text,
    category text,
    status text,
    visibility text,
    module text,
    is_library_reference boolean,
    source_prompt_id uuid,
    updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
    select ci.id,
           ci.title,
           ci.slug,
           ci.summary,
           ci.content,
           ci.category,
           ci.status::text,
           ci.visibility::text,
           ci.module,
           ci.library_ref_catalog_prompt_id is not null,
           coalesce(ci.library_ref_catalog_prompt_id, ci.source_template_id),
           ci.updated_at
      from public.content_items ci
     where ci.id = p_content_item_id
       and ci.owner_user_id = (select auth.uid())
       and ci.type = 'prompt'
       and ci.module in ('kommun', 'valvet')
       and ci.status <> 'archived';
$$;

revoke all on function public.get_my_connect_library_prompt(uuid) from public;
grant execute on function public.get_my_connect_library_prompt(uuid) to authenticated;