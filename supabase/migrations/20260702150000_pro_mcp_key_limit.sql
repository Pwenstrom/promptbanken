-- Gör MCP-nyckelgränsen plan-medveten: Free stannar på 1, Pro får 5.
-- Ersätter enforce_mcp_key_limit() från 20260628130000_plan_limits.sql,
-- som hade 1 hårdkodat oavsett plan.

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
            key_limit := case when workspace_record.plan = 'pro' then 5 else 1 end;

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
