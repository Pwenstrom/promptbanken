# Promptbanken – kodbasspecifika säkerhetsregler

Regler som är specifika för Promptbanken och som en generisk granskare inte kan
härleda. Flagga varje diff som bryter mot dessa.

## Två världar – MCP-nyckelscope (hård gräns)

- **Personliga MCP-nycklar** (nycklar på `workspaces.type='personal'`) får BARA nå
  personlig värld: användarens egna prompts + delade addon-ytor (`plan='start'`,
  `license_id IS NULL`) där nyckelns ägare är medlem.
- En personlig Pro-nyckel får ALDRIG returnera mallar från Förvaltning/Kommun-ytor
  (`plan IN ('plus','enterprise')` eller `license_id IS NOT NULL`) – oavsett
  parametrar. Detta är en hård säkerhetsgräns. Varna om någon ändring i
  `get_workspace_prompts_for_key` kan låta en personlig nyckel nå en licensyta.
- **Organisationsnycklar** (nycklar på licensytor) gäller bara sin egen org-yta.
  Blanda aldrig personlig och organisationsvärld i samma svar.
- `get_workspace_prompts_for_key(p_key_hash, p_scope, p_workspace_id)` är
  kontextstyrd: utan `p_workspace_id` returneras BARA privat yta. Den får aldrig
  auto-returnera alla delade ytor i ett default-anrop.
- En personlig nyckel får aldrig returnera en ANNAN medlems privata prompts.

## Delade addon-ytor vs org-licenser

- En delad arbetsyta är `type='organization'`, `plan='start'`, `license_id IS NULL`
  + en rad i `shared_workspace_addons`. Den får ALDRIG skapa en `pro_licenses`-rad.
- `pro_licenses` hör bara till Förvaltning (`plus`) och Kommun (`enterprise`).
- Gränser för addon-ytor (medlemmar, mallar) läses från `shared_workspace_addons`,
  aldrig från `pro_licenses`. Org-licensytor läser från `pro_licenses`.
- Addon-ytor har 0 egna MCP-nycklar – `enforce_mcp_key_limit` måste blockera
  nyckelskapande på org-ytor med `license_id IS NULL`.
- Alla medlemmar i en delad addon-yta måste ha aktiv Pro-rättighet. Använd alltid
  `app_private.has_active_pro_entitlement(user_id)`, aldrig en hårdkodad
  "self-paid pro"-koll.
- `create_shared_workspace()` är enda vägen till en ny delad yta.
  `create_pro_order()` måste avvisa `plan='start'`.

## RLS och SECURITY DEFINER

- Alla `SECURITY DEFINER`-funktioner MÅSTE ha `set search_path = ''` och referera
  scheman explicit (`public.`, `app_private.`). Flagga definer-funktioner utan det.
- RLS ska vara den verkliga behörighetsgränsen. Frontendkontroller (t.ex.
  `isAdminRole`, `api_enabled`-koll i `admin.js`) är BARA för UX – lita aldrig på
  dem för säkerhet. Ny känslig åtkomst måste enforceras i RLS/trigger, inte bara i JS.
- Publik/anonym läsning av `content_items` får bara omfatta
  `status='published' AND visibility='public'`. Varna om en policy vidgar `anon`-läsning.
- Funktioner exponerade till `anon` (t.ex. nyckel-hash-baserade RPC:er) får bara
  läcka data som legitimt hör till den nyckeln/den publika ytan.

## Nycklar och hemligheter

- Frontend får BARA använda Supabase publishable key (`VITE_SUPABASE_PUBLISHABLE_KEY`).
  `service_role`/secret keys får aldrig förekomma i frontend, i bundlad kod eller i
  versionerade filer. Flagga varje `sb_secret_`, service-role-JWT eller `sk-...` i diffen.
- MCP-nycklar: 256 bitars slump (`pb_` + 32 slumpbytes), SHA-256-hashade. Det lagrade
  `api_keys.key_hash` ÄR behörigheten (skickas som `p_key_hash`) – behandla det som en
  hemlighet, logga aldrig ut det, exponera det aldrig i UI/API-svar.
- Inga hemligheter i `.env.example`, README, migrationer, seed eller testfiler –
  bara platshållare. `.env`, `.env.seed.local` och loggfiler ska vara gitignore:ade.

## GDPR / dataminimering

- Tjänsten lagrar inga personuppgifter. Snabbinmatningstext och promptinnehåll som
  användaren klistrar in får aldrig skickas till server eller lagras (utom lokalt i
  webbläsaren). Flagga nya nätverksanrop som skickar användarens fritext till en server.
- Compliance-status ska vara sanningsenlig: påstå aldrig i copy/README att tjänsten
  är granskad av dataskyddssamordnare/juridik (den är inte det – status är väntande).

## script.js

- `script.js` buntas inte av Vite och serveras rått. Den får aldrig innehålla
  `import`/`export` – håll den self-contained.
