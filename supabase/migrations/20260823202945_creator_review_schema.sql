-- Delprojekt 4: redaktionellt granskningsflöde för creator-innehåll.
-- Se docs/superpowers/specs/2026-08-23-creator-review-flow-design.md.
--
-- Denna migration lägger bara till schema. RPC:erna ligger i
-- 20260823091000_creator_review_read_rpcs.sql och
-- 20260823093000_creator_review_decision_rpcs.sql, distributionsgaten i
-- 20260823094000_catalog_read_creator_gate.sql.

-- 1. Nya samtycken på källtabellerna ---------------------------------------
--
-- creator_consent_shared (delprojekt 3) betyder "får publiceras i öppna
-- Promptbanken" och täcker inte vidaredistribution till tredjepartsklienter
-- som ChatGPT. Därför två nya, separata fält.

alter table public.content_items
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;

comment on column public.content_items.creator_consent_distribution is
    'Sant om creatorn godkänt att innehållet distribueras via Promptbanken Open/MCP till externa AI-klienter. Skilt från creator_consent_shared, som bara gäller publicering i öppna Promptbanken.';

comment on column public.content_items.creator_rights_attested is
    'Sant om creatorn intygat att innehållet är eget eller att hen har rätt att sprida det.';

alter table public.creator_package_drafts
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false,
    add column if not exists review_note text;

comment on column public.creator_package_drafts.creator_consent_distribution is
    'Som content_items.creator_consent_distribution, fast för ett paket-utkast.';

comment on column public.creator_package_drafts.creator_rights_attested is
    'Som content_items.creator_rights_attested, fast för ett paket-utkast.';

comment on column public.creator_package_drafts.review_note is
    'Redaktionell återkoppling när ett utkast skickats tillbaka eller avslagits. Visas för creatorn i creator-packages.html.';

-- 2. Granskningsresultat ---------------------------------------------------

create table if not exists public.creator_submission_screenings (
    id uuid primary key default gen_random_uuid(),
    subject_type text not null check (subject_type in ('prompt', 'package')),
    subject_id uuid not null,
    verdict text not null check (verdict in ('gron', 'gul', 'rod')),
    findings jsonb not null default '[]'::jsonb,
    suggested_feedback text,
    rules_version text not null,
    model text not null,
    created_by uuid not null references auth.users(id),
    created_at timestamptz not null default now()
);

comment on table public.creator_submission_screenings is
    'Append-only logg av AI-förgranskningar. Rådgivande: ingenting här får styra publicering. subject_id pekar på content_items eller creator_package_drafts beroende på subject_type, medvetet utan foreign key så historiken överlever att ett utkast raderas.';

create index if not exists creator_submission_screenings_subject_idx
    on public.creator_submission_screenings (subject_type, subject_id, created_at desc);

alter table public.creator_submission_screenings enable row level security;

-- Ingen policy för anon eller authenticated. Läsning sker via de
-- platform_owner-gatade RPC:erna, skrivning via edge-funktionens
-- service-role. En creator ska inte se AI-omdömet om sitt eget inskick.

-- 3. Attribution i katalogen ----------------------------------------------
--
-- Distributionsflaggorna kopieras in vid godkännande i stället för att
-- läsas via join: katalograden ska bära sitt eget bevis för att den får
-- distribueras. En creator som ändrar sig i sin arbetsyta ska inte tyst
-- ändra distributionsläget för redan publicerat innehåll.

alter table public.catalog_prompts
    add column if not exists creator_profile_id uuid references public.creator_profiles(id) on delete set null,
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;

alter table public.catalog_packages
    add column if not exists creator_profile_id uuid references public.creator_profiles(id) on delete set null,
    add column if not exists creator_consent_distribution boolean not null default false,
    add column if not exists creator_rights_attested boolean not null default false;

comment on column public.catalog_prompts.creator_profile_id is
    'Satt när katalogposten kommer från ett godkänt creator-inskick. Null för kurerat redaktionellt innehåll. Distributionsgaten i list_published_* utesluter poster där denna är satt.';

comment on column public.catalog_packages.creator_profile_id is
    'Satt när katalogposten kommer från ett godkänt creator-inskick. Null för kurerat redaktionellt innehåll. Distributionsgaten i list_published_* utesluter poster där denna är satt.';

create index if not exists catalog_prompts_creator_profile_idx
    on public.catalog_prompts (creator_profile_id) where creator_profile_id is not null;

create index if not exists catalog_packages_creator_profile_idx
    on public.catalog_packages (creator_profile_id) where creator_profile_id is not null;
