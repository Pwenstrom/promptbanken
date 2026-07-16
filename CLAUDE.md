# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See [AGENTS.md](AGENTS.md) for multi-agent workflow conventions, common commands, verification steps, and code/architecture rules used in this project.

## Commands

**Frontend (Vite + vanilla JS):**
```powershell
npm run web:dev   # start dev server on 0.0.0.0
npm run build     # build to dist/
npm run preview   # preview the built output
```

**MCP server (Python, stdio):**
```powershell
npm run setup:python   # create .venv and install requirements.txt in mcp-server/
npm run dev            # start the MCP stdio server (blocks, awaits MCP client input)
cd mcp-server && npm run dev  # same, from mcp-server subfolder
```

**Backend requirements** live in `backend/requirements.txt` and are installed into `backend/.venv` by the setup script.

There are no automated tests; manual verification uses the browser dev console (regression test stubs exist inline in `script.js`).

## Architecture

### Two separate runtimes

1. **Web app** — a multi-page static site (Vite, no framework). HTML pages are in the root (`index.html`, `admin.html`, `login.html`, `local-chat.html`, etc.). JS modules live in `src/` (Supabase auth/admin) and the main prompt-browsing logic is entirely in `script.js` (vanilla, loaded directly into `index.html`). CSS is in `style.css`. Vite bundles `src/*.js` for the admin/auth pages only; `script.js` and `style.css` are served as-is.

2. **MCP server** — a Python stdio server in `mcp-server/server/` built with `FastMCP`. Runs locally, one process per user, started by the user's own MCP client (nyckel via env var, not HTTP header). It exposes tools including `list_skills`, `get_skill`, `route_skill`, `compile_skill_prompt`, `check_input_risk`, and Pro-gated read tools (`list_pro_templates`, `list_my_private_prompts`, `list_my_shared_workspaces`, `list_shared_workspace_prompts`). The Node.js scripts in `mcp-server/scripts/` only handle Python venv discovery and spawning — they contain no business logic.

**Separat repo `mcp_promptbanken`** hostar en egen, delad MCP-server i Docker på VPS:en (`mcp.promptbanken.se`) — samma Supabase-databas, men annan kodbas/process, nyckel via `X-MCP-Key`-header per anrop istället för env var. Write-verktyg (`save_workspace_prompt`) byggs där, inte i detta repos `mcp-server/`.

### Data flow for prompt cards

`prompts.json` → fetched at runtime by `loadPrompts()` in `script.js` → each entry's `.file` path is fetched as plain text → `createPromptCard()` builds DOM. Prompt metadata (category, audience, role, risk) is stored separately in two in-memory maps (`promptUiMeta`, `mcpPromptMeta`) keyed by prompt ID. The MCP server reads the same `skills.json` and `prompts/*.txt` files but independently via `SkillRepository`.

### Prompt content lives in two registries

- `prompts.json` — UI registry (title, description, file path, security_examples). Used by the web frontend.
- `skills.json` — MCP registry (intents, roles, audiences, risk_level, output_type). Used by the MCP server.
- Both point to the same `prompts/*.txt` files as source of truth for the actual prompt text.
- When adding a new prompt, update **both** JSON files and create the `.txt` file.

### Supabase workspace model

The admin UI (`src/admin.js`, `admin.html`) uses Supabase for auth and stores prompts in `content_items`. The role hierarchy is `viewer < editor < workspace_admin < workspace_owner < platform_owner`. Row-level security is enforced in Supabase; the frontend enforces the same rules client-side for UX only. Supabase credentials are injected via `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` env vars (never the service key in frontend code).

Personal workspaces (free plan) are capped at 3 active prompts. Organization workspaces can share prompts within the workspace. Only `platform_owner` can publish prompts with `visibility: 'public'` to the global library.

### Quick input and export flow

The global quick-input textarea (id `quick-input-textarea`) stores its value in `quickInputText`. When a prompt is copied, `replaceInputMarkers()` substitutes `[klistra in här]` and `[TEXT]` placeholders with this value. The "Anpassa prompt" export modal adds role/audience/tone/length/format headers to the prompt text. No user input is ever sent to a server or persisted beyond `sessionStorage` for local chat.

### Local chat

"Chatta lokalt" stores a seed payload in `sessionStorage` under `promptbankenLocalChatSeed` and navigates to `local-chat.html`. That page streams from `BACKEND_BASE_URL/api/chat/stream` (a local Ollama-style backend, base URL auto-detected from `window.location.origin`). The local run backend is **separate** from the MCP server and the Supabase backend.

### MCP skill routing

`SkillRouter.route()` scores skills by term overlap (4 pts per matching term), role match (3 pts), and audience match (2 pts). Swedish characters are normalised (`å→a`, `ä→a`, `ö→o`) before comparison. Fallback skills when no match: `klarsprak`, `sammanfattning`, `mejl`.

`RiskChecker` uses regex patterns to flag personnummer, e-mail, phone numbers, and case reference numbers in user input before prompt compilation — it never blocks, only warns.

## Key constraints

- **GDPR / EU AI Act**: All prompts are tools for human decision-making; the service stores no personal data. Quick-input text is local-only (never transmitted). Each prompt card has `security_examples` reminding users to anonymise before copying.
- **Prompt text files** (`prompts/*.txt`) are the canonical source; the two JSON registries reference them.
- `script.js` is not bundled by Vite — keep it self-contained with no `import` statements.
- The MCP server runs as a stdio process; it must never start an HTTP server of its own.
