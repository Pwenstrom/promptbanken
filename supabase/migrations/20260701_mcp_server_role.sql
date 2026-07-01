-- Begränsad Postgres-roll för MCP-servern.
-- Ersätter service-role-nyckeln i mcp_promptbanken/.env på VPS:en.
--
-- Bakgrund: service-role bypassar RLS helt och ger läs/skriv på ALLA
-- tabeller. MCP-servern behöver bara anropa två RPC-funktioner, så den
-- ska inte ha mer access än så. Blir VPS:en/containern komprometterad
-- kan angriparen bara anropa verify_mcp_key/get_workspace_prompts med
-- en hash — inte dumpa content_items, api_keys eller några andra tabeller.
--
-- Denna migration är rent additiv: den skapar en ny roll och nya grants,
-- och ändrar inga befintliga rättigheter för anon/authenticated/public.
-- Promptbankens frontend (anon/publishable-nyckel) berörs inte.

create role mcp_server nologin noinherit;

-- Får använda schemat, men inga tabellrättigheter
grant usage on schema app_private to mcp_server;

-- Endast de två funktionerna MCP-servern faktiskt anropar
grant execute on function app_private.verify_mcp_key(text)       to mcp_server;
grant execute on function app_private.get_workspace_prompts(uuid) to mcp_server;

-- PostgREST/GoTrue autentiserar som "authenticator" och byter sedan roll
-- baserat på JWT:ns "role"-claim. Utan denna grant kan authenticator
-- inte växla till mcp_server, och anrop skulle nekas.
grant mcp_server to authenticator;
