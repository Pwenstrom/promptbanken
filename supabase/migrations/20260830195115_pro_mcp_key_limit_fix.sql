-- supabase/migrations/20260901090000_pro_mcp_key_limit_fix.sql
-- Fixar drift mellan den enforcerande triggern (5, satt
-- 20260702150000_pro_mcp_key_limit.sql) och det UI/RPC faktiskt visar
-- (3, get_plan_usage, 20260718120000_plan_usage_valvet_fields.sql).
-- Beslutat: 3 är rätt gräns -- matchar vad Pro-användare sett sedan
-- 18 juli. Se docs/superpowers/specs/2026-08-30-connect-my-library-
-- architecture-analysis.md sektion P.4.

create or replace function app_private.enforce_mcp_key_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    workspace_record public.workspaces%rowtype;
    existing_count   integer;
    key_limit        integer;
begin
    if new.scopes @> array['mcp']::text[] then
        select * into workspace_record
          from public.workspaces
         where id = new.workspace_id;

        if workspace_record.type = 'personal' then
            key_limit := case when workspace_record.plan = 'pro' then 3 else 1 end;

            select count(*) into existing_count
              from public.api_keys
             where workspace_id = new.workspace_id
               and scopes @> array['mcp']::text[]
               and revoked_at is null;

            if existing_count >= key_limit then
                raise exception 'Personliga konton på %-planen kan ha max % aktiva MCP-nycklar.', workspace_record.plan, key_limit;
            end if;
        end if;
    end if;
    return new;
end;
$$;

revoke all on function app_private.enforce_mcp_key_limit() from public;
