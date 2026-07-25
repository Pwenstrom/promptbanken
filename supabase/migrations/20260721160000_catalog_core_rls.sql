-- Katalogtabellerna (Task 1) skapades utan RLS -- avvikelse från repots
-- genomgående konvention (varje annan public-tabell har enable row level
-- security, se t.ex. 20260612121000_rls_policies.sql) och en verklig lucka:
-- Supabase beviljar som standard CRUD på public-scheman till anon/authenticated,
-- vilket gjorde det möjligt att skriva/publicera direkt mot PostgREST:s
-- tabellendpoints och kringgå platform-owner-kollen i write-RPC:erna
-- (20260721150000_catalog_write_rpc_authorization.sql) helt, samt läsa
-- opublicerade drafts direkt utan de publicerade read-RPC:ernas
-- status='published'-filter. Ingen policy läggs till -- RLS på utan policy
-- nekar all direkt åtkomst, medan security definer-RPC:erna (ägda av en
-- priviligierad roll) fortsätter fungera oförändrat eftersom RLS inte
-- gäller för dem.

alter table public.catalog_prompts          enable row level security;
alter table public.catalog_prompt_variants  enable row level security;
alter table public.catalog_packages         enable row level security;
alter table public.catalog_package_variants enable row level security;
alter table public.catalog_package_items    enable row level security;

revoke all on public.catalog_prompts          from anon, authenticated;
revoke all on public.catalog_prompt_variants  from anon, authenticated;
revoke all on public.catalog_packages         from anon, authenticated;
revoke all on public.catalog_package_variants from anon, authenticated;
revoke all on public.catalog_package_items    from anon, authenticated;
