-- Delningar: creator-brandade länkar till eget publicerat innehåll.
-- Se docs/superpowers/specs/2026-08-24-creator-ux-structure.md.
--
-- Fyra beslut som formar tabellerna nedan:
--
-- 1. Bara publicerat får delas. En delning kan alltså aldrig bli en väg
--    förbi granskningen. "Publicerat" betyder en rad i catalog_prompts
--    eller catalog_packages med status 'published' och creator_profile_id
--    som pekar på delarens egen profil.
-- 2. Delningssidor indexeras aldrig. Sidan sätter noindex; det här
--    schemat behöver inget för det, men beslutet förklarar varför inget
--    här är byggt för sökbarhet.
-- 3. Versionslåsning görs med en riktig kopia i content_snapshots, inte
--    med ett versionsnummer. Samma tabell är avsedd att användas av
--    snapshot-steget i creator-granskningen.
-- 4. Statistiken lagras dygnsaggregerad från början — en rad per delning,
--    händelsetyp och datum, med en räknare. Det finns alltså ingen
--    tidsstämpel per visning att missbruka, och det är en egenskap hos
--    lagringen snarare än ett löfte i en policy.

-- 1. Innehållskopior ------------------------------------------------------

create table if not exists public.content_snapshots (
    id uuid primary key default gen_random_uuid(),
    subject_type text not null check (subject_type in ('prompt', 'package')),
    subject_id uuid not null,
    payload jsonb not null,
    created_at timestamptz not null default now()
);

comment on table public.content_snapshots is
    'Frysta kopior av publicerat innehåll. Används av delningar med låst version, och är avsedd även för snapshot-steget i creator-granskningen.';

alter table public.content_snapshots enable row level security;
revoke all on public.content_snapshots from anon, authenticated;

-- 2. Delningar ------------------------------------------------------------

create table if not exists public.creator_shares (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    subject_type text not null check (subject_type in ('prompt', 'package')),
    subject_id uuid not null,
    token text not null unique,
    snapshot_id uuid references public.content_snapshots(id) on delete set null,
    label text,
    expires_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now()
);

comment on column public.creator_shares.snapshot_id is
    'Satt när delningen är låst till en version. Null betyder följ senaste, alltså läs katalogen live.';

comment on column public.creator_shares.expires_at is
    'Null betyder tills vidare. Utgången delning svarar med ett upphört-läge, inte 404.';

create index if not exists creator_shares_owner_idx on public.creator_shares (owner_user_id, created_at desc);

alter table public.creator_shares enable row level security;
revoke all on public.creator_shares from anon, authenticated;

-- 3. Statistik, dygnsaggregerad -------------------------------------------

create table if not exists public.creator_share_events (
    share_id uuid not null references public.creator_shares(id) on delete cascade,
    event_type text not null check (event_type in ('view', 'copy')),
    occurred_on date not null default current_date,
    event_count integer not null default 0,
    primary key (share_id, event_type, occurred_on)
);

comment on table public.creator_share_events is
    'En rad per delning, händelsetyp och dygn. Ingen tidsstämpel per händelse, ingen uppgift om enhet, webbläsare eller hänvisande sida.';

alter table public.creator_share_events enable row level security;
revoke all on public.creator_share_events from anon, authenticated;

-- 4. Bygg en innehållskopia ----------------------------------------------

create or replace function app_private.build_content_payload(
    p_subject_type text,
    p_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_payload jsonb;
begin
    if p_subject_type = 'prompt' then
        select jsonb_build_object(
                   'kind', 'prompt',
                   'slug', cp.slug,
                   'title', v.title,
                   'summary', v.summary,
                   'prompt_text', v.prompt_text,
                   'example_input', v.example_input,
                   'audience_label', v.audience_label,
                   'tone_hint', v.tone_hint,
                   'risk_level', v.risk_level,
                   'security_examples', to_jsonb(coalesce(v.security_examples, array[]::text[]))
               )
          into v_payload
          from public.catalog_prompts cp
          join public.catalog_prompt_variants v
            on v.prompt_id = cp.id and v.context_key = 'generell'
         where cp.id = p_subject_id and cp.status = 'published';
    else
        select jsonb_build_object(
                   'kind', 'package',
                   'slug', cpkg.slug,
                   'package_type', cpkg.package_type,
                   'title', v.title,
                   'summary', v.summary,
                   'intro_text', v.intro_text,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'title', pv.title,
                                  'summary', pv.summary,
                                  'prompt_text', pv.prompt_text
                              ) order by cpi.sort_order)
                         from public.catalog_package_items cpi
                         join public.catalog_prompts p on p.id = cpi.prompt_id
                         join public.catalog_prompt_variants pv
                           on pv.prompt_id = p.id and pv.context_key = 'generell'
                        where cpi.package_id = cpkg.id and p.status = 'published'
                   ), '[]'::jsonb)
               )
          into v_payload
          from public.catalog_packages cpkg
          join public.catalog_package_variants v
            on v.package_id = cpkg.id and v.context_key = 'generell'
         where cpkg.id = p_subject_id and cpkg.status = 'published';
    end if;

    return v_payload;
end;
$$;

-- 5. Skapa en delning -----------------------------------------------------

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
    v_token text := encode(gen_random_bytes(16), 'hex');
    v_share_id uuid;
begin
    if v_user is null then
        raise exception 'Du måste vara inloggad.';
    end if;

    if p_subject_type not in ('prompt', 'package') then
        raise exception 'Okänd typ: %. Ange prompt eller package.', p_subject_type;
    end if;

    select id into v_profile_id from public.creator_profiles where user_id = v_user;
    if v_profile_id is null then
        raise exception 'Du behöver en creator-profil för att kunna dela innehåll.';
    end if;

    -- Bara eget publicerat innehåll. Det är den regel som gör att en
    -- delning aldrig kan bli en väg förbi granskningen.
    if p_subject_type = 'prompt' then
        select exists (
            select 1 from public.catalog_prompts
             where id = p_subject_id and status = 'published'
               and creator_profile_id = v_profile_id
        ) into v_owns;
    else
        select exists (
            select 1 from public.catalog_packages
             where id = p_subject_id and status = 'published'
               and creator_profile_id = v_profile_id
        ) into v_owns;
    end if;

    if not v_owns then
        raise exception 'Du kan bara dela ditt eget publicerade innehåll. Utkast och innehåll under granskning går inte att dela.';
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

create or replace function public.create_creator_share(
    p_subject_type text,
    p_subject_id uuid,
    p_pin_version boolean default false,
    p_expires_at timestamptz default null,
    p_label text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select app_private.create_creator_share(p_subject_type, p_subject_id, p_pin_version, p_expires_at, p_label);
$$;

revoke all on function public.create_creator_share(text, uuid, boolean, timestamptz, text) from public;
grant execute on function public.create_creator_share(text, uuid, boolean, timestamptz, text) to authenticated;

-- 6. Creatorns egna delningar --------------------------------------------

create or replace function public.list_my_creator_shares()
returns table (
    id uuid,
    subject_type text,
    subject_id uuid,
    token text,
    label text,
    title text,
    pinned boolean,
    expires_at timestamptz,
    revoked_at timestamptz,
    is_active boolean,
    views integer,
    copies integer,
    created_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
    select s.id,
           s.subject_type,
           s.subject_id,
           s.token,
           s.label,
           coalesce(
               (select v.title from public.catalog_prompt_variants v
                 where v.prompt_id = s.subject_id and v.context_key = 'generell'),
               (select v.title from public.catalog_package_variants v
                 where v.package_id = s.subject_id and v.context_key = 'generell'),
               s.label
           ) as title,
           s.snapshot_id is not null as pinned,
           s.expires_at,
           s.revoked_at,
           s.revoked_at is null and (s.expires_at is null or s.expires_at > now()) as is_active,
           coalesce((select sum(e.event_count)::integer from public.creator_share_events e
                      where e.share_id = s.id and e.event_type = 'view'), 0) as views,
           coalesce((select sum(e.event_count)::integer from public.creator_share_events e
                      where e.share_id = s.id and e.event_type = 'copy'), 0) as copies,
           s.created_at
      from public.creator_shares s
     where s.owner_user_id = (select auth.uid())
     order by s.created_at desc;
$$;

revoke all on function public.list_my_creator_shares() from public;
grant execute on function public.list_my_creator_shares() to authenticated;

-- 7. Avsluta och förlänga -------------------------------------------------

create or replace function public.revoke_creator_share(p_share_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    update public.creator_shares
       set revoked_at = now()
     where id = p_share_id
       and owner_user_id = (select auth.uid())
       and revoked_at is null
    returning id into v_id;

    if v_id is null then
        raise exception 'Delningen hittades inte, tillhör inte dig, eller är redan avslutad.';
    end if;

    return jsonb_build_object('id', v_id, 'revoked', true);
end;
$$;

revoke all on function public.revoke_creator_share(uuid) from public;
grant execute on function public.revoke_creator_share(uuid) to authenticated;

create or replace function public.extend_creator_share(p_share_id uuid, p_expires_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    update public.creator_shares
       set expires_at = p_expires_at
     where id = p_share_id
       and owner_user_id = (select auth.uid())
       and revoked_at is null
    returning id into v_id;

    if v_id is null then
        raise exception 'Delningen hittades inte, tillhör inte dig, eller är avslutad.';
    end if;

    return jsonb_build_object('id', v_id, 'expires_at', p_expires_at);
end;
$$;

revoke all on function public.extend_creator_share(uuid, timestamptz) from public;
grant execute on function public.extend_creator_share(uuid, timestamptz) to authenticated;

-- 8. Den publika läsvägen -------------------------------------------------
--
-- Anonym. Returnerar aldrig något om varför ett token inte fungerar utöver
-- 'expired' respektive 'not_found' — inget om huruvida det någonsin funnits.

create or replace function public.get_shared_content(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_share public.creator_shares;
    v_payload jsonb;
    v_creator jsonb;
begin
    select * into v_share from public.creator_shares where token = p_token;

    if v_share.id is null then
        return jsonb_build_object('state', 'not_found');
    end if;

    if v_share.revoked_at is not null
       or (v_share.expires_at is not null and v_share.expires_at <= now()) then
        return jsonb_build_object('state', 'expired');
    end if;

    if v_share.snapshot_id is not null then
        select s.payload into v_payload
          from public.content_snapshots s where s.id = v_share.snapshot_id;
    else
        v_payload := app_private.build_content_payload(v_share.subject_type, v_share.subject_id);
    end if;

    -- Innehållet kan ha avpublicerats efter att delningen skapades.
    if v_payload is null then
        return jsonb_build_object('state', 'expired');
    end if;

    select jsonb_build_object('display_name', prof.display_name, 'slug', prof.slug)
      into v_creator
      from public.creator_profiles prof
     where prof.user_id = v_share.owner_user_id
       and prof.status = 'published';

    insert into public.creator_share_events (share_id, event_type, occurred_on, event_count)
    values (v_share.id, 'view', current_date, 1)
    on conflict (share_id, event_type, occurred_on)
    do update set event_count = public.creator_share_events.event_count + 1;

    return jsonb_build_object(
        'state', 'ok',
        'pinned', v_share.snapshot_id is not null,
        'expires_at', v_share.expires_at,
        'creator', v_creator,
        'content', v_payload
    );
end;
$$;

revoke all on function public.get_shared_content(text) from public;
grant execute on function public.get_shared_content(text) to anon, authenticated;

create or replace function public.record_share_copy(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    select id into v_id from public.creator_shares
     where token = p_token
       and revoked_at is null
       and (expires_at is null or expires_at > now());

    if v_id is null then
        return jsonb_build_object('recorded', false);
    end if;

    insert into public.creator_share_events (share_id, event_type, occurred_on, event_count)
    values (v_id, 'copy', current_date, 1)
    on conflict (share_id, event_type, occurred_on)
    do update set event_count = public.creator_share_events.event_count + 1;

    return jsonb_build_object('recorded', true);
end;
$$;

revoke all on function public.record_share_copy(text) from public;
grant execute on function public.record_share_copy(text) to anon, authenticated;
