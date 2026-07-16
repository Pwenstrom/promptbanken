-- supabase/tests/verify_valvet_limits_and_locking.sql
-- Körs manuellt mot staging efter Task 1-3. Kräver ett Free-personligt
-- test-workspace (slug 'test-free-personal', se seed-scriptet) inloggat
-- via en riktig auth-session (auth.uid() måste matcha workspacets
-- owner_user_id för dessa INSERT/UPDATE-satser -- kör som den användaren,
-- t.ex. via Supabase SQL Editor "Run as user" eller en client-driven
-- session, INTE som service_role).

-- V1 -- 50 valvet-items ska gå bra, den 51:a ska blockeras.
-- (Kör i en loop eller upprepa manuellt -- visar principen för en post:)
insert into public.content_items (workspace_id, owner_user_id, created_by, type, module, title, slug, content, status, visibility)
select w.id, w.owner_user_id, w.owner_user_id, 'prompt', 'valvet', 'V1 test', 'v1-test-' || gen_random_uuid()::text, 'innehåll', 'draft', 'private'
from public.workspaces w where w.slug = 'test-free-personal';
-- Förväntat vid rad 51: ERROR 'Du har nått gränsen på 50 insättningar i Valvet.'

-- V2 -- modul-låsning: försök ändra module på en befintlig valvet-rad.
update public.content_items set module = 'kommun'
where module = 'valvet' and workspace_id = (select id from public.workspaces where slug = 'test-free-personal') limit 1;
-- Förväntat: ERROR 'module kan inte ändras efter att en post skapats.'

-- V3 -- synlighetslås: försök sätta visibility='workspace' på en valvet-rad.
update public.content_items set visibility = 'workspace'
where module = 'valvet' and workspace_id = (select id from public.workspaces where slug = 'test-free-personal') limit 1;
-- Förväntat: ERROR 'Valvet stödjer bara privata insättningar i denna version.'

-- V4 -- arkiverade räknas inte mot taket: arkivera en post, försök skapa en ny (ska gå bra igen).
update public.content_items set status = 'archived'
where module = 'valvet' and workspace_id = (select id from public.workspaces where slug = 'test-free-personal') limit 1;
insert into public.content_items (workspace_id, owner_user_id, created_by, type, module, title, slug, content, status, visibility)
select w.id, w.owner_user_id, w.owner_user_id, 'prompt', 'valvet', 'V4 test', 'v4-test-' || gen_random_uuid()::text, 'innehåll', 'draft', 'private'
from public.workspaces w where w.slug = 'test-free-personal';
-- Förväntat: lyckas (arkiveringen frigjorde en plats under taket).

-- V5 -- återställning räknas mot taket: om workspacet nu har exakt 50 aktiva
-- (efter V4 fyllde platsen igen), försök återställa den arkiverade från V4.
update public.content_items set status = 'draft'
where module = 'valvet' and status = 'archived'
  and workspace_id = (select id from public.workspaces where slug = 'test-free-personal') limit 1;
-- Förväntat: ERROR 'Du har nått gränsen på 50 insättningar i Valvet.'
