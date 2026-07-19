# Promptpaket Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aktivera/avaktivera promptpaket (de 7 områdena) i Valvet + per-mall-kopiering till eget valv.

**Architecture:** En migration i `promptbanken` (RLS-tabell `valvet_package_activations` + RPC `copy_template_to_valvet` som speglar `copy_catalog_item_to_valvet` med `pro_prompt_templates` som källa). UI-sektion i Valvets "Bläddra i Promptbanken"-flik, direkt Supabase-CRUD via RLS.

**Tech Stack:** Postgres/Supabase, vanilla JS.

**Spec:** `docs/superpowers/specs/2026-07-19-promptpaket-design.md` — alla fält-/policy-detaljer där.

## Global Constraints

- Kvot delas med katalogkopior (Free 5/mån, `app_private.valvet_catalog_copies`; loggens `source_content_item_id` bär template-id, ingen FK).
- Ingen dedup för template-kopior (dokumenterat beslut i specen).
- Ingen MCP-ändring (delprojekt 4).
- `security definer` + `set search_path=''` + schemakvalificering.
- Migration mot live via Supabase MCP `apply_migration` (Peters mandat).

### Task 1: Migration + checklista (`promptbanken`)

- [ ] `supabase/tests/verify_valvet_packages.sql`: RLS-negativtest, aktivera/avaktivera-rundtur, Free-kopiering räknas mot kvoten, kopians fält (type='prompt', category=area_label, content=prompt_text, status='draft', visibility='private', source='catalog_copy', source_content_item_id null).
- [ ] `supabase/migrations/20260719110000_valvet_packages.sql`: tabell + RLS-policies (select/insert/delete, personligt workspace via profiles-join, `(select auth.uid())`) + grants; `app_private.copy_template_to_valvet(p_template_id)` (kvotgren, slug-loop, set_config, insert, logg) + public wrapper med grant till authenticated.
- [ ] Applicera via MCP, kör checklistans efter-frågor.
- [ ] Commit.

### Task 2: UI (`valvet_promptbanken`)

- [ ] `vault.html`: sektion "Promptpaket" (container + status-element) ovanför katalog-listan i Bläddra-fliken, befintliga komponentklasser.
- [ ] `src/vault.js`: ladda `list_pro_templates` + aktiveringar vid flikvisning; gruppera på `area`; rendera områdesrader med Aktivera/Avaktivera (insert/delete `valvet_package_activations`); aktiverade paket expanderade med mall-rader + "Kopiera till mitt Valv" → `rpc('copy_template_to_valvet')`; sökfältet filtrerar även paketmallar klientside.
- [ ] `npm run build` grönt. Commit.

### Task 3: Deploy + verifiering

- [ ] Push båda repos.
- [ ] Browser: aktivera paket → mallar syns → kopiera → syns i Mina insättningar → avaktivera (kopian kvar).
- [ ] Uppdatera minnesfil.
