# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Organizational users writing citizen/customer-facing or internal text with AI
assistance — originally Swedish kommun caseworkers (handläggare), now broader
across plan tiers (Free, Pro, Delad arbetsyta, Förvaltning). Users work
either directly in the web catalog (browse/copy prompt cards) or connect
Promptbanken to their own AI client (ChatGPT, Claude, etc.) via MCP.

## Product Purpose

Promptbanken provides ready-made, GDPR/EU AI Act-conscious prompt templates
(klarspråk, mejl, FAQ, checklistor, möten, informationsutskick) so
organizations can produce clearer, safer AI-assisted communication without
building prompts from scratch or risking personal-data exposure.

## Positioning

Not just a prompt library: an integrated, privacy-conscious work layer that
helps AI clients find, adapt, and use the right template directly inside the
user's own workflow (via MCP tools: list_skills, get_skill, route_skill,
compile_skill_prompt) — not merely a copy-paste catalog a competitor could
clone by scraping prompt text.

## Operating Context

- Web catalog (`index.html`, `promptbanken.html`) for direct browse/copy use.
- MCP server (local stdio, one process per user) and a separate hosted MCP
  (`mcp.promptbanken.se`) for AI-client integration, per-request key auth.
- Supabase-backed workspace model for Pro/org tiers: personal workspaces
  (Free, capped at 3 active prompts), shared org workspaces, admin UI.
- Local chat mode (`local-chat.html`) streams to a local Ollama-style backend,
  fully separate from Supabase/MCP.

## Capabilities and Constraints

- Two content registries (`prompts.json` for web UI, `skills.json` for MCP)
  both pointing to the same `prompts/*.txt` source files; both must be kept
  in sync when adding content.
- No user input is ever transmitted to a server or persisted beyond
  `sessionStorage`, by design (GDPR constraint, not a gap).
- Role hierarchy: viewer < editor < workspace_admin < workspace_owner <
  platform_owner. Only platform_owner can publish prompts with public
  visibility to the global library.
- `script.js` must stay dependency-free (no `import`), served unbundled.

## Brand Commitments

Name: Promptbanken. Swedish-language product and UI throughout.

## Evidence on Hand

No fabricated testimonials, case studies, or customer logos on hand —
future work must not invent these. Existing prompt cards carry real
`security_examples` content as authored in `prompts.json`/`prompts/*.txt`.

## Product Principles

- Compliance is a feature, not a constraint: every prompt card reminds users
  to anonymize before copying; no server-side storage of user input.
- Meet users where they already work: catalog browsing and MCP-native
  integration are equally first-class, not one a fallback for the other.
- Plan tiers (Free/Pro/Delad arbetsyta/Förvaltning) gate scale and sharing,
  not core safety or template quality.
- Swedish public-sector-grade trust bar applies even as the user base
  broadens beyond kommun.

## Accessibility & Inclusion

EN 301 549 V3.2.1, including requirements equivalent to WCAG 2.1 level AA,
per Swedish DOS-lagen (offentlig sektor digital accessibility law).
