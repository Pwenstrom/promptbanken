-- Promptbanken MVP initial schema.
-- Review before running: this creates new public tables, enum types, indexes, and triggers.
-- It intentionally does not drop or alter existing project objects.

create extension if not exists pgcrypto with schema extensions;

do $$
begin
    create type public.workspace_type as enum ('personal', 'organization');
exception
    when duplicate_object then null;
end $$;

do $$
begin
    create type public.workspace_plan as enum ('free', 'start', 'plus', 'pro', 'enterprise');
exception
    when duplicate_object then null;
end $$;

do $$
begin
    create type public.workspace_status as enum ('active', 'suspended');
exception
    when duplicate_object then null;
end $$;

do $$
begin
    create type public.profile_role as enum (
        'platform_owner',
        'workspace_owner',
        'workspace_admin',
        'editor',
        'viewer'
    );
exception
    when duplicate_object then null;
end $$;

do $$
begin
    create type public.content_item_type as enum (
        'prompt',
        'routine',
        'checklist',
        'guide',
        'faq',
        'document',
        'template'
    );
exception
    when duplicate_object then null;
end $$;

do $$
begin
    create type public.content_status as enum ('draft', 'review', 'published', 'archived');
exception
    when duplicate_object then null;
end $$;

do $$
begin
    create type public.content_visibility as enum ('public', 'workspace', 'private');
exception
    when duplicate_object then null;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create or replace function public.set_content_published_at()
returns trigger
language plpgsql
as $$
begin
    if new.status = 'published' and new.published_at is null then
        new.published_at = now();
    end if;

    return new;
end;
$$;

create table if not exists public.workspaces (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    slug text not null,
    type public.workspace_type not null default 'organization',
    plan public.workspace_plan not null default 'free',
    status public.workspace_status not null default 'active',
    owner_user_id uuid not null references auth.users(id) on delete restrict,
    max_public_items integer not null default 25 check (max_public_items >= 0),
    max_documents integer not null default 25 check (max_documents >= 0),
    api_enabled boolean not null default false,
    mcp_enabled boolean not null default false,
    rag_enabled boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint workspaces_slug_key unique (slug),
    constraint workspaces_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$')
);

create table if not exists public.profiles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    role public.profile_role not null default 'viewer',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint profiles_user_workspace_key unique (user_id, workspace_id)
);

create table if not exists public.content_items (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    owner_user_id uuid references auth.users(id) on delete set null,
    type public.content_item_type not null,
    title text not null,
    slug text not null,
    summary text,
    content text not null,
    status public.content_status not null default 'draft',
    visibility public.content_visibility not null default 'workspace',
    category text,
    audience text,
    created_by uuid references auth.users(id) on delete set null,
    published_at timestamptz,
    updated_at timestamptz not null default now(),
    constraint content_items_workspace_slug_key unique (workspace_id, slug),
    constraint content_items_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{1,120}[a-z0-9]$'),
    constraint content_items_published_at_check check (
        (status = 'published' and published_at is not null)
        or (status <> 'published')
    )
);

create table if not exists public.files (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    content_item_id uuid references public.content_items(id) on delete set null,
    filename text not null,
    storage_path text not null,
    mime_type text,
    file_size bigint check (file_size is null or file_size >= 0),
    uploaded_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    constraint files_storage_path_key unique (storage_path)
);

create table if not exists public.api_keys (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    created_by uuid references auth.users(id) on delete set null,
    name text not null,
    key_prefix text not null,
    key_hash text not null,
    scopes text[] not null default '{}',
    last_used_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    constraint api_keys_key_prefix_key unique (key_prefix),
    constraint api_keys_key_hash_key unique (key_hash)
);

create index if not exists workspaces_owner_user_id_idx on public.workspaces (owner_user_id);
create index if not exists profiles_user_id_idx on public.profiles (user_id);
create index if not exists profiles_workspace_id_idx on public.profiles (workspace_id);
create index if not exists profiles_workspace_role_idx on public.profiles (workspace_id, role);
create index if not exists content_items_workspace_id_idx on public.content_items (workspace_id);
create index if not exists content_items_owner_user_id_idx on public.content_items (owner_user_id);
create index if not exists content_items_created_by_idx on public.content_items (created_by);
create index if not exists content_items_workspace_status_visibility_idx
    on public.content_items (workspace_id, status, visibility);
create index if not exists content_items_published_public_idx
    on public.content_items (workspace_id, published_at desc)
    where status = 'published' and visibility = 'public';
create index if not exists files_workspace_id_idx on public.files (workspace_id);
create index if not exists files_content_item_id_idx on public.files (content_item_id);
create index if not exists api_keys_workspace_id_idx on public.api_keys (workspace_id);
create index if not exists api_keys_active_prefix_idx
    on public.api_keys (key_prefix)
    where revoked_at is null;

drop trigger if exists set_workspaces_updated_at on public.workspaces;
create trigger set_workspaces_updated_at
before update on public.workspaces
for each row execute function public.set_updated_at();

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists set_content_items_updated_at on public.content_items;
create trigger set_content_items_updated_at
before update on public.content_items
for each row execute function public.set_updated_at();

drop trigger if exists set_content_items_published_at on public.content_items;
create trigger set_content_items_published_at
before insert or update on public.content_items
for each row execute function public.set_content_published_at();
