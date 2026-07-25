# Task 1 Report: Global Context Filter

## Status

Implemented Task 1 for the global context filter. The work is limited to the specified frontend changes and does not include static prompt filtering or fallback badges.

## Changes

- Moved the context control from the open-catalog section to a global bar immediately below the page introduction.
- Added the required heading, explanation, radiogroup container, and active-context status line.
- Replaced the multi-select checkbox UI with exclusive pill buttons for Alla, Kommun, Skola, Företag, Förening, and Privat.
- Replaced JSON-list storage with a single active context key in the existing `promptbankenContextProfiles` localStorage key.
- Added `DEFAULT_CONTEXT_KEY`, `GLOBAL_CONTEXT_OPTIONS`, `loadGlobalContextSelection()`, `saveGlobalContextSelection()`, `getActiveContextKey()`, and `renderGlobalContextStatus()`.
- Preserved the existing Supabase RPC function calls and payload property names. Each call now passes the single selected context as a one-item `p_context_keys` array.
- Re-rendered the context buttons, status line, open-catalog prompts, and open-catalog packages from the same click flow.
- Updated the empty state to describe one selected context rather than multiple profile selections.

## Verification

Command run:

```powershell
npm run build
```

Result: passed. Vite completed successfully, copied the static assets, and the generated `dist/` files contain the global context markup, styles, and JavaScript.

## Scope Exclusions

- No filtering of the static `prompts.json` catalog was added.
- No fallback badges or labels were added.
- No Supabase RPC names, endpoints, or database behavior were changed.

## Concern

The prior UI stored a JSON array under the same localStorage key. Task 1's specified single-value loader uses the stored value directly, so users with an existing multi-select value may need to select a context again before their stored preference is normalized.

## Fix Round 1

### Changes

- Migrated legacy JSON-array values in `promptbankenContextProfiles` to the first valid context key, with `generell` as the fallback, and persisted the normalized value. This resolves the earlier concern about existing multi-select values.
- Rendered the unavailable-state message in both the prompt and package grids.
- Added roving `tabindex` plus Arrow, Home, and End keyboard navigation to the context radiogroup.

### Verification

Command run:

```powershell
npm run build
```

Result: passed. Vite completed successfully and copied 25 static files.
