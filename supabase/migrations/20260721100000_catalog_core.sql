-- Katalogkärnans tabeller: prompts, packages, och deras kontextvarianter.
--
-- Denna migration definierar de fem huvudtabeller som utgör grunden för
-- den dynamiska katalogplattformen. Editors kan skapa prompts/packages
-- som drafts, lägga till kontextvarianter, och publicera för både webben
-- och MCP-servern.

create table if not exists public.catalog_prompts (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    status text not null check (status in ('draft', 'published')),
    prompt_kind text not null default 'prompt',
    icon_key text,
    image_key text,
    color_theme text,
    created_by uuid,
    updated_by uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.catalog_prompt_variants (
    id uuid primary key default gen_random_uuid(),
    prompt_id uuid not null references public.catalog_prompts(id) on delete cascade,
    context_key text not null check (context_key in ('generell', 'skola', 'kommun', 'företag', 'förening', 'privat')),
    title text not null,
    summary text not null,
    prompt_text text not null,
    example_input text,
    audience_label text,
    tone_hint text,
    context_notes text,
    suggested_variables jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint catalog_prompt_variants_prompt_context_key unique (prompt_id, context_key)
);

create table if not exists public.catalog_packages (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    status text not null check (status in ('draft', 'published')),
    package_type text not null check (package_type in ('collection', 'workflow')),
    icon_key text,
    image_key text,
    color_theme text,
    created_by uuid,
    updated_by uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.catalog_package_variants (
    id uuid primary key default gen_random_uuid(),
    package_id uuid not null references public.catalog_packages(id) on delete cascade,
    context_key text not null check (context_key in ('generell', 'skola', 'kommun', 'företag', 'förening', 'privat')),
    title text not null,
    summary text not null,
    intro_text text,
    audience_label text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint catalog_package_variants_package_context_key unique (package_id, context_key)
);

create table if not exists public.catalog_package_items (
    id uuid primary key default gen_random_uuid(),
    package_id uuid not null references public.catalog_packages(id) on delete cascade,
    prompt_id uuid not null references public.catalog_prompts(id) on delete restrict,
    sort_order integer not null,
    step_title text,
    step_intro text,
    is_required boolean not null default true,
    constraint catalog_package_items_package_prompt_key unique (package_id, prompt_id)
);

-- Triggrar för updated_at-kolumner
drop trigger if exists set_catalog_prompts_updated_at on public.catalog_prompts;
create trigger set_catalog_prompts_updated_at
before update on public.catalog_prompts
for each row execute function public.set_updated_at();

drop trigger if exists set_catalog_prompt_variants_updated_at on public.catalog_prompt_variants;
create trigger set_catalog_prompt_variants_updated_at
before update on public.catalog_prompt_variants
for each row execute function public.set_updated_at();

drop trigger if exists set_catalog_packages_updated_at on public.catalog_packages;
create trigger set_catalog_packages_updated_at
before update on public.catalog_packages
for each row execute function public.set_updated_at();

drop trigger if exists set_catalog_package_variants_updated_at on public.catalog_package_variants;
create trigger set_catalog_package_variants_updated_at
before update on public.catalog_package_variants
for each row execute function public.set_updated_at();
