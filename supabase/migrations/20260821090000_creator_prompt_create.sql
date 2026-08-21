-- Låter en inloggad användare skapa en ny prompt i sin personliga
-- arbetsyta direkt från creator-content.html, i stället för att bara kunna
-- skicka in prompts som redan finns där (som tidigare bara gick att skapa
-- via MCP-skrivvägen, som dessutom kräver Pro).
--
-- Återanvänder ensure_personal_workspace() och slugify_candidate() från
-- befintliga migrationer, samt den befintliga triggern
-- enforce_content_access_model för Free-planens 3-prompt-tak (dess
-- felmeddelande "Free-läge är begränsat till 3 privata prompts." får
-- bubbla upp oförändrat).

create or replace function app_private.create_my_creator_prompt(
    p_title text,
    p_content text,
    p_category text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_workspace_id uuid;
    v_candidate_slug text;
    v_suffix integer := 0;
    v_row public.content_items%rowtype;
begin
    if auth.uid() is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    if trim(coalesce(p_title, '')) = '' or length(p_title) > 200 then
        raise exception 'Titel krävs (max 200 tecken).';
    end if;

    if trim(coalesce(p_content, '')) = '' or length(p_content) > 20000 then
        raise exception 'Prompttext krävs (max 20000 tecken).';
    end if;

    v_workspace_id := public.ensure_personal_workspace();

    v_candidate_slug := app_private.slugify_candidate(p_title, 'prompt');
    while exists (
        select 1 from public.content_items
         where workspace_id = v_workspace_id and slug = v_candidate_slug
    ) loop
        v_suffix := v_suffix + 1;
        v_candidate_slug := substr(app_private.slugify_candidate(p_title, 'prompt'), 1, 110)
            || '-' || v_suffix::text;
    end loop;

    insert into public.content_items (
        workspace_id, owner_user_id, created_by, type, title, slug, content,
        category, status, visibility, source
    ) values (
        v_workspace_id, auth.uid(), auth.uid(), 'prompt', trim(p_title), v_candidate_slug, trim(p_content),
        nullif(trim(coalesce(p_category, '')), ''), 'draft', 'private', 'manual'
    )
    returning * into v_row;

    return jsonb_build_object('id', v_row.id, 'title', v_row.title, 'slug', v_row.slug, 'status', v_row.status);
end;
$$;

create or replace function public.create_my_creator_prompt(
    p_title text,
    p_content text,
    p_category text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.create_my_creator_prompt(p_title, p_content, p_category);
$$;

revoke all on function public.create_my_creator_prompt(text, text, text) from public;
grant execute on function public.create_my_creator_prompt(text, text, text) to authenticated;
