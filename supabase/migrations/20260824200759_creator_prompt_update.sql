-- Låter creatorn redigera ett eget utkast.
--
-- Utan detta är återkopplingsslingan verkningslös: adminet skickar tillbaka
-- en prompt med en motivering, creatorn läser den — och kan inte göra
-- något åt den. Enda vägen var att skapa en ny prompt och överge den gamla.
--
-- Gränser: bara egna poster, bara status 'draft'. En prompt som ligger i
-- 'review' ska dras tillbaka först, annars kunde innehållet ändras under
-- fötterna på granskaren. Publicerat innehåll redigeras inte härifrån alls.
--
-- Slug lämnas orörd även när titeln ändras. Den är intern och används för
-- att hålla isär poster i arbetsytan; att låta den vandra skulle bara
-- riskera krockar utan att ge något.

create or replace function app_private.update_my_creator_prompt(
    p_content_item_id uuid,
    p_title text,
    p_content text,
    p_summary text default null,
    p_category text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
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

    if length(coalesce(p_summary, '')) > 500 then
        raise exception 'Sammanfattningen får vara högst 500 tecken.';
    end if;

    update public.content_items
       set title = trim(p_title),
           content = trim(p_content),
           summary = nullif(trim(coalesce(p_summary, '')), ''),
           category = nullif(trim(coalesce(p_category, '')), ''),
           updated_at = now()
     where id = p_content_item_id
       and owner_user_id = (select auth.uid())
       and status = 'draft'
    returning * into v_row;

    if v_row.id is null then
        raise exception 'Prompten hittades inte, tillhör inte dig, eller är inte ett utkast. Dra tillbaka den från granskning först om du vill ändra den.';
    end if;

    return jsonb_build_object(
        'id', v_row.id,
        'title', v_row.title,
        'summary', v_row.summary,
        'status', v_row.status
    );
end;
$$;

create or replace function public.update_my_creator_prompt(
    p_content_item_id uuid,
    p_title text,
    p_content text,
    p_summary text default null,
    p_category text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.update_my_creator_prompt(p_content_item_id, p_title, p_content, p_summary, p_category);
$$;

revoke all on function public.update_my_creator_prompt(uuid, text, text, text, text) from public;
grant execute on function public.update_my_creator_prompt(uuid, text, text, text, text) to authenticated;

-- Creatorn behöver se sin egen prompttext och kategori för att kunna
-- redigera dem. list_my_creator_prompts returnerade varken.
drop function if exists public.list_my_creator_prompts();

create or replace function public.list_my_creator_prompts()
returns table (
    id uuid,
    title text,
    slug text,
    summary text,
    content text,
    category text,
    status text,
    visibility text,
    creator_consent_shared boolean,
    creator_consent_reusable boolean,
    review_note text,
    updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select ci.id, ci.title, ci.slug, ci.summary, ci.content, ci.category,
           ci.status::text, ci.visibility::text,
           ci.creator_consent_shared, ci.creator_consent_reusable, ci.review_note,
           ci.updated_at
      from public.content_items ci
     where ci.owner_user_id = (select auth.uid())
       and ci.type = 'prompt'
       and ci.module = 'kommun'
     order by ci.updated_at desc;
$$;

revoke all on function public.list_my_creator_prompts() from public;
grant execute on function public.list_my_creator_prompts() to authenticated;
