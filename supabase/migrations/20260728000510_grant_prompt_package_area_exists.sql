-- Fix: activating a Valvet package failed with
-- "permission denied for function prompt_package_area_exists".
--
-- app_private.prompt_package_area_exists(text) was introduced in
-- 20260720120000_valvet_template_provenance_and_package_validation.sql and
-- re-created identically in 20260727141513_repair_valvet_provenance_schema.sql.
-- Both migrations `revoke all ... from public` on it but never follow up with
-- a `grant execute ... to` statement, unlike every sibling helper in the same
-- migrations (public.copy_template_to_valvet_for_key, public.activate_package_for_key,
-- public.list_active_packages_for_key all get an explicit grant to anon).
-- It is called from app_private.activate_package_for_key,
-- app_private.list_active_packages_for_key, and the
-- app_private.enforce_known_prompt_package_area trigger -- reachable via both
-- the anon+key hosted MCP flow and authenticated web app writes to Valvet.

grant execute on function app_private.prompt_package_area_exists(text) to anon;
grant execute on function app_private.prompt_package_area_exists(text) to authenticated;
