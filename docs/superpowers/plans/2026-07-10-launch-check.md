# Launch-Check: Free/Pro/Delad Arbetsyta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the specific, verified gaps between the current admin dashboard and the "launch-ready for public test" bar defined in the Free/Pro/Delad arbetsyta launch-check spec — without re-building anything that already works.

**Architecture:** All changes live in the existing single-page admin dashboard (`admin.html` + `src/admin.js`, vanilla JS, Supabase client, no framework, no bundler-side test runner). Per `CLAUDE.md`, this project has no automated test suite — verification is manual, in the browser dev console, or (for this session) via a temporary-script-disable + mock-data technique already established in this codebase's own history for testing authenticated-only views without logging in. Every task's "test" steps use that same approach.

**Tech Stack:** Vanilla JS (ES modules), Supabase JS client v2, Vite (dev server only, no bundler-side tests), PostgreSQL/PostgREST via Supabase RPC and RLS.

## Global Constraints

- No new frontend framework, no new dependency. Stay vanilla JS matching the rest of `src/admin.js`.
- `script.js` (the public catalog page) is a separate runtime from `admin.js` and is out of scope for this plan — every task here touches `admin.html`/`src/admin.js` only, unless stated otherwise.
- Never invent numeric plan limits (prompt caps, member caps, price points) that aren't already defined in `app_private.plan_limits()` (`supabase/migrations/20260706102500_addon_no_own_keys.sql`) or `planPricing`/`nextStepsByPlan` in `src/admin.js`. If a task needs a number, it reads it from those existing sources, never hardcodes a new one.
- All user-facing strings are Swedish, matching the existing tone in `src/admin.js` (plain, direct, no exclamation marks, sentence case).
- Database changes are new SQL migration files under `supabase/migrations/`, following this repo's `YYYYMMDDHHMMSS_description.sql` naming and the "safe to run twice" (`create or replace function`) convention already used throughout. Per `supabase/README.md`, migrations in this repo are applied manually by the project owner — do not attempt to execute them against a live database from a task; the task's deliverable is the migration *file*, plus a stated instruction that it still needs to be run.
- Every task that touches `admin.html` must use the existing "temp-disable" verification technique to actually render the changed markup without an authenticated session, because `src/admin.js`'s `requireSession()` redirects to `login.html` otherwise:
  1. Comment out the `<script type="module" src="/src/admin.js"></script>` tag at the bottom of `admin.html` (wrap it as `<!-- TEMP-VISUAL-QA-DISABLE ... -->`).
  2. Remove the `hidden` attribute from `<section class="admin-dashboard" data-admin-dashboard hidden>`.
  3. Run `npm run build`, view the built page (or dev server), inject any needed mock state via a one-off browser JS snippet.
  4. Revert both temporary edits before committing (`git diff --stat admin.html` must show no changes when done).

---

### Task 1: Stop raw Postgres/RLS errors from reaching users

**Files:**
- Modify: `src/admin.js:186-189` (add helper functions right after `setStatus`)
- Modify: `src/admin.js` — 30 call sites listed below, each changes one line

**Interfaces:**
- Produces: `isRawDatabaseError(message: string): boolean`, `setErrorStatus(error: {message?: string} | null, fallbackMessage: string): void`, `getErrorMessage(error: {message?: string} | null, fallbackMessage: string): string` — used by every subsequent task that reports a Supabase error to the user.

**Problem:** Every error handler in `src/admin.js` currently does `setStatus(error.message || 'Friendly Swedish fallback', true)`. This means whenever `error.message` is non-empty, it is shown *instead of* the friendly fallback — including when that message is a raw Postgres/PostgREST string like `new row violates row-level security policy for table "content_items"` or `duplicate key value violates unique constraint "profiles_pkey"`. Custom exceptions raised by this project's own RPCs (e.g. `invite_org_member`, `delete_workspace`) are already good, human Swedish text and should still pass through unchanged — only genuine raw-database text should be intercepted.

- [ ] **Step 1: Add the detection + wrapper functions**

In `src/admin.js`, immediately after the existing `setStatus` function (currently at line 186-189), add:

```js
const RAW_DB_ERROR_PATTERNS = [
  'row-level security',
  'permission denied',
  'violates foreign key constraint',
  'violates unique constraint',
  'violates check constraint',
  'duplicate key value',
  'jwt',
  'pgrst',
  'failed to fetch',
  'networkerror',
  'relation "',
  'column "'
];

function isRawDatabaseError(message) {
  if (!message) return false;
  const lower = message.toLowerCase();
  return RAW_DB_ERROR_PATTERNS.some((pattern) => lower.includes(pattern));
}

function getErrorMessage(error, fallbackMessage) {
  const raw = error?.message || '';
  if (!raw) return fallbackMessage;
  return isRawDatabaseError(raw) ? fallbackMessage : raw;
}

function setErrorStatus(error, fallbackMessage) {
  setStatus(getErrorMessage(error, fallbackMessage), true);
}
```

- [ ] **Step 2: Verify the helper in isolation**

Since there is no test runner in this project, verify directly in the browser console on any loaded page (e.g. `http://localhost:5173/admin.html`, no login needed — this only tests a pure function once pasted in):

```js
// Paste isRawDatabaseError's body inline to check, or open admin.html,
// paste the whole Step 1 block into the console, then:
console.log(isRawDatabaseError('new row violates row-level security policy for table "content_items"')); // true
console.log(isRawDatabaseError('Du saknar behörighet att bjuda in medlemmar till det här workspacet.')); // false
console.log(getErrorMessage({ message: 'duplicate key value violates unique constraint "profiles_pkey"' }, 'Kunde inte lägga till medlemmen.')); // 'Kunde inte lägga till medlemmen.'
console.log(getErrorMessage({ message: 'Alla medlemmar i en delad arbetsyta måste ha en aktiv Pro-plan.' }, 'Kunde inte bjuda in medlem.')); // passes the custom message through unchanged
console.log(getErrorMessage({ message: '' }, 'Kunde inte spara.')); // 'Kunde inte spara.'
```

Expected: the five `console.log` lines print exactly the five values commented above.

- [ ] **Step 3: Replace every `setStatus(error.message || '...', true)` call site**

Each of these is a mechanical one-line change from `setStatus(error.message || 'X', true);` to `setErrorStatus(error, 'X');`. Line numbers are from the current file; re-`grep -n "error.message ||" src/admin.js` first if any earlier task in this plan has already shifted line numbers.

```
934:    setStatus(error.message || 'Kunde inte skapa MCP-nyckel.', true);
952:    setStatus(error.message || 'Kunde inte återkalla MCP-nyckel.', true);
1086:    setStatus(error.message || 'Kunde inte ladda arbetsytor.', true);
1221:    setStatus(error.message || 'Kunde inte skapa prompten.', true);
1305:    setStatus(error.message || 'Kunde inte bjuda in medlem.', true);
1378:    setStatus(error.message || 'Kunde inte radera arbetsytan.', true);
1411:    setStatus(error.message || 'Kunde inte skapa join-länk.', true);
1433:    setStatus(error.message || 'Kunde inte återkalla join-länken.', true);
1674:    setStatus(error.message || 'Kunde inte byta namn.', true);
1819:    setStatus(error.message || 'Kunde inte spara prompt.', true);
1877:    setStatus(error.message || 'Kunde inte ta bort prompt.', true);
1902:    setStatus(error.message || 'Kunde inte avpublicera prompt.', true);
1923:    setStatus(error.message || 'Kunde inte publicera prompt.', true);
1972:    setStatus(error.message || 'Kunde inte skapa API-nyckel.', true);
2026:    setStatus(error.message || 'Kunde inte markera som fakturerad.', true);
2041:    setStatus(error.message || 'Kunde inte markera som betald.', true);
2053:    setStatus(error.message || 'Kunde inte aktivera beställningen.', true);
2065:    setStatus(error.message || 'Kunde inte nedgradera beställningen.', true);
2093:    setStatus(error.message || 'Kunde inte skapa inbjudan.', true);
2121:    setStatus(error.message || 'Kunde inte göra användaren till admin.', true);
2174:    setStatus(error.message || 'Kunde inte återkalla API-nyckel.', true);
2186:    setStatus(error.message || 'Kunde inte logga ut.', true);
2224:      setStatus(error.message || 'Kunde inte byta arbetsyta.', true);
2395:    refreshWorkspaceData().catch((error) => setStatus(error.message || 'Kunde inte uppdatera.', true));
2529:      setStatus(error.message || 'Kunde inte byta arbetsyta.', true);
2550:      setStatus(error.message || 'Kunde inte radera arbetsytan.', true);
2575:  setStatus(error.message || 'Kunde inte ladda adminytan.', true);
```

For each, change `setStatus(error.message || 'X', true)` to `setErrorStatus(error, 'X')` (drop the `, true` — it's baked into `setErrorStatus`). For the two arrow-function one-liners (lines 2395 and originally at 2276 for `setUpgradeStatus`, see below), change:

```js
refreshWorkspaceData().catch((error) => setStatus(error.message || 'Kunde inte uppdatera.', true));
```
to:
```js
refreshWorkspaceData().catch((error) => setErrorStatus(error, 'Kunde inte uppdatera.'));
```

- [ ] **Step 4: Handle the two special-cased call sites separately**

Line 1339 builds a per-workspace status object instead of calling `setStatus` directly:
```js
state.workspaceInviteStatus[workspaceId] = { message: error.message || 'Kunde inte bjuda in medlem.', isError: true };
```
Change to:
```js
state.workspaceInviteStatus[workspaceId] = { message: getErrorMessage(error, 'Kunde inte bjuda in medlem.'), isError: true };
```

Line 2152 (inside `deleteAccount`, reading from an Edge Function response, not a Supabase client error) builds a message from two possible sources:
```js
const message = data?.error || error.message || 'Kunde inte radera kontot.';
```
Change to:
```js
const message = data?.error || getErrorMessage(error, 'Kunde inte radera kontot.');
```
(`data?.error` is this project's own Edge Function's own Swedish text — already safe, checked first, unchanged.)

- [ ] **Step 5: Handle the two `setUpgradeStatus` call sites**

Lines 1631 and 2276 use `setUpgradeStatus` (a separate status-display function for the upgrade form, not `setStatus`). Since `setErrorStatus` currently hardcodes a call to `setStatus`, extend it to accept an optional status function:

```js
function setErrorStatus(error, fallbackMessage, statusFn = setStatus) {
  statusFn(getErrorMessage(error, fallbackMessage), true);
}
```

Then:
```js
// line 1631, was: setUpgradeStatus(error.message || 'Kunde inte skapa beställningen.', true);
setErrorStatus(error, 'Kunde inte skapa beställningen.', setUpgradeStatus);

// line 2276, was: confirmUpgradeOrder().catch((error) => setUpgradeStatus(error.message || 'Kunde inte skapa beställningen.', true));
confirmUpgradeOrder().catch((error) => setErrorStatus(error, 'Kunde inte skapa beställningen.', setUpgradeStatus));
```

- [ ] **Step 6: Verify no `error.message ||` pattern remains**

```bash
grep -n "error.message ||" src/admin.js
```
Expected: no output (empty).

```bash
node --input-type=module --check < src/admin.js
```
Expected: no output (syntax OK).

```bash
npm run build
```
Expected: build succeeds, no errors.

- [ ] **Step 7: Commit**

```bash
git add src/admin.js
git commit -m "Stop raw Postgres/RLS error text from reaching users in admin.js"
```

---

### Task 2: Onboarding banner for a brand-new personal (Free/Pro) workspace

**Files:**
- Modify: `admin.html:104` (insert new section right after the existing org-only `id="kom-igang"` section closes, before the `.admin-stat-grid` div at line 106)
- Modify: `src/admin.js:351` (add a sibling function next to `renderOnboardingChecklist`)
- Modify: `src/admin.js:1712` (call the new function alongside the existing one)

**Interfaces:**
- Consumes: `state.workspace.type`, `state.prompts` (array of content_items, already loaded by `refreshWorkspaceData` before this runs), `state.mcpKeys` (already loaded) — same state shape `renderOnboardingChecklist` already reads.
- Produces: nothing consumed elsewhere; this is a leaf render function.

**Problem:** `renderOnboardingChecklist()` (`src/admin.js:351`) only runs for `state.workspace?.type === 'organization'` (guarded at the top of that function, and the section itself has `data-org-only` in the HTML). A brand-new Free or Pro user — the majority of first-time signups — lands on an empty dashboard with no "what do I do first" guidance at all.

- [ ] **Step 1: Add the HTML section**

In `admin.html`, insert this new section immediately after the closing `</section>` of `id="kom-igang"` (currently line 104) and before `<div class="admin-stat-grid" ...>` (currently line 106):

```html
                    <section class="workspace-section admin-onboarding" id="kom-igang-personlig" data-personal-only hidden>
                        <div class="workspace-section-heading">
                            <div>
                                <h2>Välkommen till Promptbanken</h2>
                                <p>Tre saker att börja med.</p>
                            </div>
                        </div>
                        <ol class="onboarding-checklist">
                            <li data-onboarding-step="first-prompt">
                                <span class="onboarding-check" aria-hidden="true">○</span>
                                <div>
                                    <strong>Skapa din första prompt</strong>
                                    <p>Under "Mina prompts" kan du skriva en egen mall, eller kopiera och anpassa en av de öppna standardmallarna.</p>
                                </div>
                            </li>
                            <li data-onboarding-step="mcp-key">
                                <span class="onboarding-check" aria-hidden="true">○</span>
                                <div>
                                    <strong>Skapa en personlig MCP-nyckel</strong>
                                    <p>Under "Integrationer" kan du koppla ditt AI-verktyg (t.ex. Claude eller ChatGPT) direkt till dina mallar.</p>
                                </div>
                            </li>
                            <li data-onboarding-step="explore-pro">
                                <span class="onboarding-check" aria-hidden="true">○</span>
                                <div>
                                    <strong>Utforska Pro-mallarna</strong>
                                    <p>Under "Promptbibliotek" ser du vilka premiummallar som ingår om du uppgraderar till Pro.</p>
                                </div>
                            </li>
                        </ol>
                    </section>
```

- [ ] **Step 2: Add the render function**

In `src/admin.js`, immediately after the closing brace of `renderOnboardingChecklist()` (the function currently spans roughly lines 351-... up to its `return`/closing — find it via `grep -n "function renderOnboardingChecklist" -A 25 src/admin.js` to get the exact current end line), add a new sibling function:

```js
function renderPersonalOnboarding() {
  const section = document.getElementById('kom-igang-personlig');
  if (!section || state.workspace?.type !== 'personal') {
    if (section) section.hidden = true;
    return;
  }

  const ownPrompts = state.prompts.filter((item) => (
    (item.owner_user_id === state.user?.id || item.created_by === state.user?.id) && item.status !== 'archived'
  )).length;
  const hasMcpKey = state.mcpKeys.some((key) => !key.revoked_at);

  // Once the user has done at least one of the three things, the banner
  // has served its purpose -- stop showing it so the dashboard doesn't
  // nag a returning user forever.
  if (ownPrompts > 0 || hasMcpKey) {
    section.hidden = true;
    return;
  }

  section.hidden = false;

  const steps = {
    'first-prompt': ownPrompts > 0,
    'mcp-key': hasMcpKey,
    'explore-pro': false
  };

  Object.entries(steps).forEach(([step, done]) => {
    const item = section.querySelector(`[data-onboarding-step="${step}"]`);
    if (!item) return;
    item.classList.toggle('is-done', done);
    const check = item.querySelector('.onboarding-check');
    if (check) check.textContent = done ? '✓' : '○';
  });
}
```

- [ ] **Step 3: Wire it into the render lifecycle**

In `src/admin.js`, at line 1712 (inside `refreshWorkspaceData`), change:
```js
  renderOnboardingChecklist();
```
to:
```js
  renderOnboardingChecklist();
  renderPersonalOnboarding();
```

- [ ] **Step 4: Verify with the temp-disable technique**

Follow the Global Constraints temp-disable steps. Then in the browser console:

```js
// Simulate a brand-new personal workspace with zero prompts and no MCP key.
window.state = window.state || {}; // if `state` isn't already global, this step needs the real module scope -- instead paste renderPersonalOnboarding's body with a local `state` object shaped like this:
const state = {
  workspace: { type: 'personal' },
  user: { id: 'user-1' },
  prompts: [],
  mcpKeys: []
};
document.getElementById('kom-igang-personlig').hidden = false; // simulate what the function would do
```

Take a screenshot or visually confirm: the "Välkommen till Promptbanken" section renders with three unchecked (○) steps, positioned between the (still-hidden, org-only) "Kom igång som team" section and the stat-grid.

Then simulate a user who already has one prompt:
```js
document.querySelectorAll('#kom-igang-personlig [data-onboarding-step]').forEach(el => {
  if (el.dataset.onboardingStep === 'first-prompt') {
    el.classList.add('is-done');
    el.querySelector('.onboarding-check').textContent = '✓';
  }
});
```
Confirm the "Skapa din första prompt" line shows a checkmark instead of an empty circle, matching the existing org-onboarding checkbox visual style (no new CSS needed — `.onboarding-checklist`/`.onboarding-check`/`.is-done` styles already exist and are shared).

Revert the temp-disable changes per Global Constraints before committing.

- [ ] **Step 5: Commit**

```bash
git add admin.html src/admin.js
git commit -m "Add first-run onboarding banner for personal Free/Pro workspaces"
```

---

### Task 3: "Testa MCP-anslutning" on a newly created key

**Files:**
- Modify: `admin.html:616-622` (add a button inside the existing `data-new-mcp-key-panel`)
- Modify: `src/admin.js` (add a new function; call it from `createMcpKey`, currently ending around line 940)

**Interfaces:**
- Consumes: the raw plaintext key value that only exists in memory at the moment `createMcpKey` succeeds (`rawKey`, `src/admin.js:920`) — the *only* moment the plaintext is available, since only `key_hash` is ever stored. This is why the test button lives in the one-time-reveal panel, not next to existing keys in the table (those can never be tested this way — no other code path can retrieve a usable value for them again).
- Produces: nothing consumed elsewhere.

**Real constraint to verify before writing UI code:** this feature calls `https://mcp.promptbanken.se/mcp` directly from the browser via `fetch`, cross-origin from wherever `admin.html` is served. This only works if that server sends CORS headers permitting browser JS to read the response. Check this first — if it fails, the button must still degrade to a clear, honest message rather than a silent or confusing failure.

- [ ] **Step 1: Check CORS from the browser console first**

Open `admin.html` in the browser (logged in or not — this fetch doesn't need auth to observe the CORS behavor) and run in the console:

```js
fetch('https://mcp.promptbanken.se/mcp', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'promptbanken-admin-test', version: '1.0' } } })
})
  .then((r) => r.json().then((body) => console.log('status', r.status, body)))
  .catch((e) => console.error('fetch failed', e));
```

Expected one of:
- A JSON-RPC response logs (even an error like "Unauthorized" is fine — it proves the request reached the server and CORS allowed reading the response).
- A `TypeError: Failed to fetch` in the console, which means CORS is blocking it.

If it's the CORS-blocked case, **stop this task and report back** rather than building UI around a request that can never succeed from the browser — the fix in that case is server-side (adding CORS headers to the hosted MCP server), outside this repo's frontend code, and is a prerequisite for this task, not part of it.

- [ ] **Step 2: Add the button to the reveal panel**

Only proceed here if Step 1 confirmed the request is reachable. In `admin.html`, inside the existing `data-new-mcp-key-panel` div (currently lines 616-622), add a button and a status line:

```html
                                <div class="secret-reveal" data-new-mcp-key-panel hidden>
                                    <p class="secret-reveal-warning">⚠️ Nyckeln visas bara just nu och går inte att se igen. Spara den säkert (t.ex. i en lösenordshanterare) innan du lämnar sidan.</p>
                                    <div class="secret-reveal-row">
                                        <code data-new-mcp-key></code>
                                        <button type="button" data-copy-secret="new-mcp-key">Kopiera</button>
                                    </div>
                                    <button type="button" data-test-mcp-connection>Testa anslutning</button>
                                    <p class="mp-hint" data-test-mcp-connection-status></p>
                                </div>
```

- [ ] **Step 3: Add the test-connection function**

In `src/admin.js`, add this function near `createMcpKey` (after its closing brace, currently around line 941):

```js
async function testMcpConnection(rawKey) {
  const statusEl = document.querySelector('[data-test-mcp-connection-status]');
  if (!statusEl) return;

  statusEl.textContent = 'Testar anslutning...';
  statusEl.classList.remove('is-error');

  try {
    const response = await fetch('https://mcp.promptbanken.se/mcp', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${rawKey}`
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'initialize',
        params: {
          protocolVersion: '2024-11-05',
          capabilities: {},
          clientInfo: { name: 'promptbanken-admin-test', version: '1.0' }
        }
      })
    });

    if (response.ok) {
      statusEl.textContent = 'Anslutningen fungerar. Nyckeln accepterades av servern.';
    } else if (response.status === 401 || response.status === 403) {
      statusEl.textContent = 'Servern avvisade nyckeln (obehörig). Kontrollera att du kopierade hela nyckeln.';
      statusEl.classList.add('is-error');
    } else {
      statusEl.textContent = `Servern svarade med ett oväntat fel (status ${response.status}).`;
      statusEl.classList.add('is-error');
    }
  } catch {
    statusEl.textContent = 'Kunde inte nå servern. Kontrollera din internetanslutning och försök igen.';
    statusEl.classList.add('is-error');
  }
}
```

Then wire the button. Find where `[data-copy-secret]` is handled in the big click-delegation listener (`grep -n "copySecretButton" src/admin.js` to locate it) and add a sibling handler in the same `document.addEventListener('click', ...)` block:

```js
  const testMcpConnectionButton = event.target.closest('[data-test-mcp-connection]');
```
(add to the destructuring block near the other `const ... = event.target.closest(...)` lines), and:
```js
  if (testMcpConnectionButton) {
    const rawKey = document.querySelector('[data-new-mcp-key]')?.textContent;
    if (rawKey) {
      testMcpConnection(rawKey);
    }
  }
```
(add near the other `if (...Button) { ... }` blocks in the same listener).

- [ ] **Step 4: Verify**

```bash
node --input-type=module --check < src/admin.js
npm run build
```
Expected: both succeed with no errors.

Manual verification requires a real logged-in session (this task cannot be verified via the temp-disable technique, since it needs a real `createMcpKey` round-trip against Supabase to get a real plaintext key to test against a real server). Note in the PR/handoff that this specific button needs a live click-through by a human with an account before being considered done.

- [ ] **Step 5: Commit**

```bash
git add admin.html src/admin.js
git commit -m "Add a Testa anslutning button for newly created MCP keys"
```

---

### Task 4: General support contact line

**Files:**
- Modify: `admin.html` — add one line inside the existing `id="installningar"` section (currently starting at line 234)

**Interfaces:** None — static content, no new state or functions.

**Problem:** The only "Kontakta oss" text in `admin.html` today is scoped to the Förvaltning/Kommun quote-request flow (`data-upgrade-maxed`, line 158) and the "Kontakta oss" button on the next-steps upgrade tiles (`src/admin.js:728`). There is no general "something's wrong, here's how to reach us" line anywhere in the dashboard, which the launch-check spec calls out as a required trust signal for public test.

- [ ] **Step 1: Find the insertion point**

```bash
grep -n 'id="installningar"' admin.html
```
Confirm it's still at (or near) line 234. Read the section to find a natural place — right before the closing `</section>` of that workspace-mode section, or right after the workspace-name/role display block, whichever the file currently shows first. Read `admin.html` lines 234 to (234+40) to see the exact current content before inserting.

- [ ] **Step 2: Add the line**

Insert this paragraph as the last child inside the `id="installningar"` section, immediately before its closing `</section>` tag:

```html
                        <p class="mp-hint">Behöver du hjälp eller har du hittat något som inte fungerar? Kontakta oss på <a href="mailto:info@promptbanken.se">info@promptbanken.se</a> eller läs <a href="help.html">hjälpsidan</a>.</p>
```

(`mp-hint` is the existing muted-text utility class already used throughout `admin.html` — no new CSS needed. `info@promptbanken.se` is the same support address already used in `privacy.html`/`terms.html` this session — confirm with `grep -n "info@promptbanken.se" privacy.html` that it's still the current address before reusing it.)

- [ ] **Step 3: Verify**

```bash
npm run build
```
Expected: succeeds. Use the temp-disable technique from Global Constraints to visually confirm the line renders under "Inställningar" with working links (don't click the `mailto:` link — just confirm it's present and correctly formed in the rendered DOM via `document.querySelector('#installningar a[href^="mailto:"]')`).

- [ ] **Step 4: Commit**

```bash
git add admin.html
git commit -m "Add a general support contact line to Inställningar"
```

---

### Task 5: Manual mobile-flow verification (no code change)

**Files:** None modified — this task is a verification pass using the iframe-simulation technique already used successfully earlier in this project's history to test layouts at arbitrary widths (the real browser-resize tool does not affect actual layout in this environment, confirmed during the `admin-dashboard` horizontal-scroll fix).

**Interfaces:** None.

**Problem:** The launch-check spec explicitly calls out mobile as a public-test risk. This session already fixed one concrete horizontal-scroll bug on `admin.html` at mobile widths (missing `grid-template-columns` on `.admin-dashboard`), but that was found by accident while testing something else — there has been no deliberate pass checking that the five specific flows the spec names (create account, see plans, create prompt, see plan, find MCP key) are usable at a phone width end-to-end.

- [ ] **Step 1: Simulate a 375px viewport via iframe**

This exact snippet (or a close variant) was used successfully earlier this session — run it in the browser console on any page under test:

```js
const iframe = document.createElement('iframe');
iframe.id = 'qa-iframe';
iframe.style.cssText = 'position:fixed;top:0;left:0;width:375px;height:800px;border:2px solid red;z-index:99999;background:white;';
iframe.src = window.location.href;
document.body.appendChild(iframe);
await new Promise((r) => { iframe.onload = r; setTimeout(r, 2000); });
'ready';
```

- [ ] **Step 2: Check `login.html` at 375px**

Navigate the iframe (or a real phone-width window) to `login.html`. Confirm:
- Both the "Logga in" and "Skapa free-konto" tab buttons are tappable without overlapping.
- The email/password fields and the "Fortsätt med Google" button are full-width and not clipped.
- The Free/Pro plan-comparison cards (`.auth-plan-compare`) stack rather than overflow.

If anything overflows, check `document.documentElement.scrollWidth` vs `document.documentElement.clientWidth` inside the iframe's `contentDocument` — a mismatch confirms a real bug, matching the diagnostic pattern already used for the `admin-dashboard` fix this session.

- [ ] **Step 3: Check `admin.html`'s Översikt tab at 375px, logged in**

This step requires an actual logged-in session (the temp-disable technique only helps for unauthenticated markup inspection, not for exercising real interactive flows like typing into a form and submitting). Manually, on a phone or a real narrow browser window:
- Confirm the plan badge ("Free"/"Pro") is visible without scrolling sideways.
- Confirm "Skapa prompt" (Mina prompts tab) is reachable and the create-prompt form's fields are usable.
- Confirm the Integrationer tab's "Skapa MCP-nyckel" form is usable and the revealed key is copyable (long unbroken strings like the key value must not force horizontal scroll — verify `.secret-reveal-row code` still has `overflow-wrap: anywhere`, per `style.css:2401-2407` from this session's earlier work).

- [ ] **Step 4: Record findings**

If Steps 2-3 reveal an actual overflow or unusable control, that is a new bug — file it as a fresh, separately-scoped fix (not silently patched inside this verification task), following the same diagnostic method already proven this session (iframe width sweep to isolate the exact offending element, then a targeted CSS fix, not a broad rewrite).

If no bugs are found, this task's deliverable is simply confirmation — no commit needed.

---

### Task 6: Run the existing security/RLS test suite against the live database

**Files:** None modified — this task exercises files that already exist:
- `supabase/tests/rls_test_plan.sql` (200 lines, general RLS checklist)
- `supabase/tests/verify_a_mcp_boundary.sql`
- `supabase/tests/verify_b_join_rejections.sql`
- `supabase/tests/addon_member_limit.sql`
- `supabase/tests/addon_no_own_keys.sql`
- `supabase/tests/addon_prompt_limit.sql`
- `supabase/tests/context_mcp_scope.sql`

**Interfaces:** None — these are manual SQL-editor checklists (per the header comment in `rls_test_plan.sql`: "This file is not a migration. It is a commented checklist for staging verification"), not automated pgTAP suites. This task's deliverable is running them and recording pass/fail, not writing new code.

**Problem:** The launch-check spec's security section ("RLS/policies testade", "personlig MCP når inte organisationsytor", "delad arbetsyta kräver medlemskap", etc.) already has dedicated test files covering exactly these scenarios — they were written across this project's migration history specifically for the addon/shared-workspace and MCP-scoping work. There is no evidence in this session that they have actually been *run* against the live Supabase project since the fixes landed. This is a verification gap, not a missing-feature gap.

- [ ] **Step 1: Read each file's setup instructions**

Each file starts with a comment block describing required fixtures (e.g. `rls_test_plan.sql:6-12` calls for two workspaces and five specific role-holding users). Read all seven files' header comments first (`head -30` each) to build the combined fixture list — some workspaces/users can likely be shared across files rather than recreated per file.

- [ ] **Step 2: Create the fixtures in a staging/test Supabase project**

Do this in a project that is **not** the production database — per `supabase/README.md`: "Do not run these directly in production until staging has verified schema creation, RLS behavior, API exposure, and rollback/recovery expectations." If no staging project exists yet, this step blocks the rest of the task — flag that back rather than running fixture-creation against production.

- [ ] **Step 3: Run each block, recording actual vs. expected**

For each commented SQL block across the seven files, run it via the Supabase SQL editor authenticated as the role named in that block (per each file's own instructions), and compare the actual result against the "Expected:" comment directly above it. Keep a simple pass/fail list — this doesn't need special tooling, a plain text or markdown scratch file is enough (not part of this repo's tracked docs unless a failure is found and needs a linked fix).

- [ ] **Step 4: For any failure, open a fix as its own task**

Do not patch RLS policies inline as part of this verification task. If a block's actual result doesn't match its expected result, that's a real bug — scope a follow-up fix the same way every other bug this session was handled (isolate with a minimal reproduction, write the migration, verify, commit separately).

- [ ] **Step 5: Report**

Summarize which of the seven files passed cleanly, and list any specific failing blocks by file name and line number. No commit is produced by this task unless Step 4 fixes were also completed and committed under their own commit message.

---

## Self-Review

**1. Spec coverage check** — walking the original spec section by section:
- Free/Pro/Delad arbetsyta core limits and flows (sections 1-3 of the spec): already implemented and verified working earlier this session (plan_limits, enforce_mcp_key_limit, enforce_org_member_limit, enforce_content_access_model) — correctly *not* re-planned here, per Global Constraints' explicit instruction not to invent limits that already exist.
- Adminläge structure (section 4): overview/plan/prompts/Pro-mallar/MCP-nycklar/Arbetsytor panels already exist in `admin.html` — confirmed via direct file reads, not re-planned.
- "Det du inte får glömma" (section 5): onboarding → Task 2. Tomma lägen → already implemented (`emptyRow` helper, confirmed present for every list). Tydliga gränsmeddelanden → already implemented (e.g. `src/admin.js:916` gives the exact Free-plan-limit message the spec asks for almost verbatim). Planstatus → already implemented (`renderPlanInfo`/`renderPlanLimitsSummary`). Privat vs delat → already covered by existing visibility labeling in prompt tables. MCP-test → Task 3. Återkalla nyckel → already implemented (`revokeMcpKey`). Felmeddelanden → Task 1. Mobilvy → Task 5. Supportväg → Task 4.
- Launch-ready definition (section 6) "Säkerhet" bullets → Task 6.
- Section 7 ("kan vänta") is explicitly out of scope — correctly excluded from all six tasks.

**2. Placeholder scan** — every step above contains either exact code, exact grep/build/test commands with stated expected output, or (for Tasks 5-6) an exact manual procedure with a concrete pass/fail check — no "TODO", "handle appropriately", or "similar to Task N" placeholders present.

**3. Type/name consistency check** — `setErrorStatus`/`getErrorMessage`/`isRawDatabaseError` (Task 1) are the only new shared functions other tasks could plausibly reuse; no other task calls them, so there's no cross-task naming drift to catch. `renderPersonalOnboarding` (Task 2) is called once, immediately after being defined, with a consistent name throughout. `testMcpConnection` (Task 3) is defined and called with matching signature (`rawKey` string parameter) in both the definition and the click handler.
