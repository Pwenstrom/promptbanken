# Granskningsflöde, snabbskapa-beskrivning och rollinfo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give organization workspaces a real draft → review → published flow where the reviewer sees full prompt content before deciding, add a missing "Kort beskrivning" field to the per-workspace quick-create form, and show a live role explanation on the workspace-card invite form.

**Architecture:** All changes live in `admin.html` (markup for two existing forms) and `src/admin.js` (state, render functions, Supabase calls, click/submit delegation) — the same vanilla-JS, no-framework pattern already used throughout this file. One new database column (`content_items.review_note`) via a Supabase migration file that Peter applies himself in the SQL Editor, per this project's established workflow.

**Tech Stack:** Vanilla JS, Supabase JS client v2, Vite (no bundler test runner), Supabase Postgres migrations.

## Global Constraints

- No new dependencies.
- Swedish UI text must match the existing tone (direct, calm, non-technical) — reuse exact existing strings (`roleLabels`, `statusLabels`) wherever they already say what's needed; do not invent new phrasing for concepts already named in the file.
- `script.js` is a separate legacy file, not touched by this plan.
- No new permission role or behavior beyond the existing hierarchy (`viewer < editor < workspace_admin < workspace_owner < platform_owner`); every new admin-only action must use the existing `isAdminRole(state.profile.role)` gate, exactly like `publishPrompt`/`unpublishPrompt` already do.
- Design source of truth: `docs/superpowers/specs/2026-07-11-review-flow-design.md` — read it before starting if anything below is unclear about *why*, not just *what*.
- This project has no automated test suite. Verification is: `node --input-type=module --check` + `npm run build` for syntax/build, and the temp-disable technique (comment out the `<script type="module" src="/src/admin.js">` tag in `admin.html`, remove `hidden` from `<section class="admin-dashboard" data-admin-dashboard hidden>`, rebuild, inject mock `state` via browser JS, screenshot, then **revert both edits before committing**) for visual/DOM verification without a live login. A full authenticated click-through is out of scope for every task here — flag it for Peter to do manually, same as prior launch-check tasks.

---

### Task 1: Add `review_note` column

**Files:**
- Create: `supabase/migrations/20260711100000_review_note.sql`

**Interfaces:**
- Produces: `public.content_items.review_note` (nullable `text` column), consumed by Tasks 2 and 3.

- [ ] **Step 1: Write the migration**

```sql
-- Adds a place to record why a reviewer sent a prompt back to draft, so
-- the editor can see what to fix without asking in another channel.

alter table public.content_items
    add column if not exists review_note text;
```

- [ ] **Step 2: Verify it's syntactically valid**

Run: `node -e "require('fs').readFileSync('supabase/migrations/20260711100000_review_note.sql','utf8')"`
Expected: no output, exit code 0 (just confirms the file is readable UTF-8 text; this project does not run migrations in CI — Peter applies this himself in the Supabase SQL Editor, per `supabase/README.md`).

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260711100000_review_note.sql
git commit -m "Add review_note column for sending prompts back to draft"
```

Note in your final report: this migration has NOT been applied to the live database — Peter runs it himself. Tasks 2 and 3 write code that assumes this column exists; that code cannot be exercised against the live DB until Peter applies it, but it builds and type-checks regardless (Supabase JS calls are untyped strings, not compiled against the schema).

---

### Task 2: Editor side — "Skicka för granskning"

**Files:**
- Modify: `src/admin.js:1366-1376` (`loadPrompts` — add `review_note` to the select column list)
- Modify: `src/admin.js:645-668` (`renderPrompts` — the "Mina prompts" card list)
- Modify: `src/admin.js` (add `submitPromptForReview` function, near `publishPrompt`/`unpublishPrompt`, currently ending around line 2059)
- Modify: `src/admin.js:2541-2604` (click delegation — add `[data-submit-review-prompt]` handling)

**Interfaces:**
- Consumes: existing `escapeHtml`, `setStatus`, `setErrorStatus`, `loadPrompts`, `state.profile`, `state.workspace.id` — all already defined earlier in the file.
- Produces: `submitPromptForReview(promptId)` — an async function with the same shape as the existing `publishPrompt`/`unpublishPrompt` (Supabase update + `setStatus`/`setErrorStatus` + `await loadPrompts()`). Task 3 does not call this function, but follows its exact pattern for its own new function.

- [ ] **Step 1: Add `review_note` to the prompts select**

In `src/admin.js`, find this exact line (currently line 1369):

```js
    .select('id, title, slug, summary, content, status, visibility, category, audience, risk_level, owner_user_id, created_by, published_at, updated_at')
```

Replace with:

```js
    .select('id, title, slug, summary, content, status, visibility, category, audience, risk_level, owner_user_id, created_by, published_at, updated_at, review_note')
```

- [ ] **Step 2: Add the "Skicka för granskning" button and review_note banner to the card list**

In `src/admin.js`, find the `mineBody.innerHTML = ownPrompts.map(...)` block (currently lines 645-668):

```js
    mineBody.innerHTML = ownPrompts.map((item) => `
        <article class="mp-template">
          <div>
            <h3>${escapeHtml(item.title)}</h3>
            <p>${escapeHtml(item.summary || item.category || 'Ingen sammanfattning.')}</p>
          </div>
          <div><span class="mp-pill mp-status-${escapeHtml(item.status)}">${escapeHtml(statusLabels[item.status] || item.status)}</span></div>
          <div class="mp-small">${escapeHtml(item.category || '-')}</div>
          <div><span class="mp-pill mp-risk-${escapeHtml(item.risk_level)}">${escapeHtml(riskLabels[item.risk_level] || riskLabels.low)}</span></div>
          <div class="mp-menu">
            <button type="button" data-preview-prompt="${item.id}">${state.expandedPromptId === item.id ? 'Dölj' : 'Visa'}</button>
            ${item.status !== 'published'
              ? `<button type="button" data-edit-prompt="${item.id}">Redigera</button>`
              : ''}
            ${isAdminRole(state.profile.role) && item.status !== 'published'
              ? `<button type="button" data-publish-prompt="${item.id}">Publicera</button>`
              : ''}
            ${item.status !== 'published'
              ? `<button type="button" data-delete-prompt="${item.id}" data-delete-confirm="0">Ta bort</button>`
              : ''}
          </div>
        </article>
        ${state.expandedPromptId === item.id ? `<div class="mp-template-preview">${escapeHtml(item.content)}</div>` : ''}
      `).join('');
```

Replace with:

```js
    mineBody.innerHTML = ownPrompts.map((item) => `
        ${item.status === 'draft' && item.review_note
          ? `<p class="mp-hint is-error">Skickades tillbaka: ${escapeHtml(item.review_note)}</p>`
          : ''}
        <article class="mp-template">
          <div>
            <h3>${escapeHtml(item.title)}</h3>
            <p>${escapeHtml(item.summary || item.category || 'Ingen sammanfattning.')}</p>
          </div>
          <div><span class="mp-pill mp-status-${escapeHtml(item.status)}">${escapeHtml(statusLabels[item.status] || item.status)}</span></div>
          <div class="mp-small">${escapeHtml(item.category || '-')}</div>
          <div><span class="mp-pill mp-risk-${escapeHtml(item.risk_level)}">${escapeHtml(riskLabels[item.risk_level] || riskLabels.low)}</span></div>
          <div class="mp-menu">
            <button type="button" data-preview-prompt="${item.id}">${state.expandedPromptId === item.id ? 'Dölj' : 'Visa'}</button>
            ${item.status === 'draft'
              ? `<button type="button" data-edit-prompt="${item.id}">Redigera</button>`
              : ''}
            ${item.status === 'draft'
              ? `<button type="button" data-submit-review-prompt="${item.id}">Skicka för granskning</button>`
              : ''}
            ${isAdminRole(state.profile.role) && item.status !== 'published'
              ? `<button type="button" data-publish-prompt="${item.id}">Publicera</button>`
              : ''}
            ${item.status !== 'published'
              ? `<button type="button" data-delete-prompt="${item.id}" data-delete-confirm="0">Ta bort</button>`
              : ''}
          </div>
        </article>
        ${state.expandedPromptId === item.id ? `<div class="mp-template-preview">${escapeHtml(item.content)}</div>` : ''}
      `).join('');
```

(Change: the `review_note` banner is new; the Redigera button condition tightened from `item.status !== 'published'` to `item.status === 'draft'` so it's hidden while a prompt is under review; the new "Skicka för granskning" button appears only for drafts, alongside the unchanged admin-only "Publicera" button which still works for any non-published status per the existing plan — Task 3 does not remove or restrict `publishPrompt`, it stays as a direct-publish escape hatch for admins.)

- [ ] **Step 3: Add `submitPromptForReview`**

In `src/admin.js`, add this function immediately after `publishPrompt` closes (currently ends around line 2059, right before the blank line preceding `mcpKeyForm` or whatever follows — locate the closing `}` of `publishPrompt` by its `setStatus('Prompten publicerades.')` line or equivalent and insert after):

```js
async function submitPromptForReview(promptId) {
  const { error } = await supabase
    .from('content_items')
    .update({ status: 'review', review_note: null })
    .eq('id', promptId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setErrorStatus(error, 'Kunde inte skicka prompten för granskning.');
    return;
  }

  setStatus('Prompten skickades för granskning.');
  await loadPrompts();
}
```

- [ ] **Step 4: Wire the click handler**

In `src/admin.js`, inside the delegated click listener (`document.addEventListener('click', (event) => { ... })`, currently starting at line 2541), find the destructuring block of `const ... = event.target.closest(...)` declarations (currently lines 2542-2561) and add:

```js
  const submitReviewButton = event.target.closest('[data-submit-review-prompt]');
```

Then, near the other `if (...Button) { ... }` blocks in the same listener (e.g. right after the `if (publishButton) { ... }` block, currently lines 2563-2565), add:

```js
  if (submitReviewButton) {
    submitPromptForReview(submitReviewButton.dataset.submitReviewPrompt);
  }
```

- [ ] **Step 5: Verify**

```bash
node --input-type=module --check < src/admin.js
npm run build
```
Expected: both succeed with no errors.

Then use the temp-disable technique to confirm visually: comment out the `admin.js` script tag in `admin.html`, remove `hidden` from `.admin-dashboard`, rebuild, inject a mock `state.prompts` array (in the browser console, after the page loads) containing one item with `status: 'draft'` and one with `status: 'draft', review_note: 'Testkommentar'`, call `renderPrompts()`, and confirm:
- The draft without a note shows Redigera + "Skicka för granskning" + (if you also mock `state.profile.role = 'workspace_admin'`) Publicera + Ta bort, no banner.
- The draft with `review_note` shows the red "Skickades tillbaka: Testkommentar" banner above its card.

Revert both `admin.html` edits before committing (`git diff --stat admin.html` must be empty).

- [ ] **Step 6: Commit**

```bash
git add src/admin.js
git commit -m "Let editors submit their own drafts for review"
```

---

### Task 3: Reviewer side — preview + approve/send-back

**Files:**
- Modify: `src/admin.js:620-626` (`renderPrompts` — `reviewPrompts` filter)
- Modify: `src/admin.js:688-705` (`renderPrompts` — the review list markup)
- Modify: `src/admin.js` (add `sendPromptBackToDraft` function, next to `submitPromptForReview` from Task 2)
- Modify: `src/admin.js:2541-2604` (click delegation — add `[data-review-preview-prompt]` and `[data-send-back-prompt]` handling)

**Interfaces:**
- Consumes: `submitPromptForReview` is NOT called here (this task only adds the reviewer-facing actions); consumes `state.expandedPromptId` (same field the "Mina prompts" preview toggle already uses, from `src/admin.js:38`) to drive the review list's own show/hide preview, so no new state field is needed.
- Produces: `sendPromptBackToDraft(promptId)` — async function, same shape as `publishPrompt`.

- [ ] **Step 1: Narrow the review list to prompts actually submitted for review**

In `src/admin.js`, find this exact line (currently line 626):

```js
  const reviewPrompts = state.prompts.filter((item) => item.status !== 'published').slice(0, 6);
```

Replace with:

```js
  const reviewPrompts = state.prompts.filter((item) => item.status === 'review').slice(0, 6);
```

- [ ] **Step 2: Add preview toggle and the two decision buttons to the review list**

In `src/admin.js`, find the `reviewList.innerHTML = reviewPrompts.length ? ... : ...` block (currently lines 688-705):

```js
  if (reviewList) {
    reviewList.innerHTML = reviewPrompts.length
      ? reviewPrompts.map((item) => `
          <article>
            <div>
              <strong>${escapeHtml(item.title)}</strong>
              <span>${escapeHtml(item.category || 'Okategoriserad')} · ${escapeHtml(item.audience || 'Alla')}</span>
            </div>
            <div class="admin-review-actions">
              <small>${escapeHtml(item.updated_at ? new Date(item.updated_at).toLocaleDateString('sv-SE') : '')}</small>
              ${isAdminRole(state.profile.role) && item.status !== 'published'
                ? `<button type="button" data-publish-prompt="${item.id}">Publicera</button>`
                : ''}
            </div>
          </article>
        `).join('')
      : '<p>Inga förslag väntar på granskning.</p>';
  }
```

Replace with:

```js
  if (reviewList) {
    reviewList.innerHTML = reviewPrompts.length
      ? reviewPrompts.map((item) => `
          <article>
            <div>
              <strong>${escapeHtml(item.title)}</strong>
              <span>${escapeHtml(item.category || 'Okategoriserad')} · ${escapeHtml(item.audience || 'Alla')}</span>
            </div>
            <div class="admin-review-actions">
              <small>${escapeHtml(item.updated_at ? new Date(item.updated_at).toLocaleDateString('sv-SE') : '')}</small>
              <button type="button" data-preview-prompt="${item.id}">${state.expandedPromptId === item.id ? 'Dölj' : 'Visa'}</button>
              ${isAdminRole(state.profile.role)
                ? `<button type="button" data-publish-prompt="${item.id}">Godkänn &amp; publicera</button>
                   <button type="button" data-send-back-prompt="${item.id}">Skicka tillbaka</button>`
                : ''}
            </div>
          </article>
          ${state.expandedPromptId === item.id ? `<div class="mp-template-preview">${escapeHtml(item.content)}</div>` : ''}
        `).join('')
      : '<p>Inga förslag väntar på granskning.</p>';
  }
```

(The "Visa" button reuses the exact same `data-preview-prompt` attribute and `state.expandedPromptId` toggle already wired up in Task 2's Step 4's pre-existing click handler at `src/admin.js:2593-2597` — no new wiring needed for preview itself, since that handler already calls `renderPrompts()` on toggle, and `renderPrompts()` re-renders both the card list and this review list from the same `state.prompts`. The "Godkänn & publicera" button reuses the existing `[data-publish-prompt]` handler and `publishPrompt()` function unchanged — approving is exactly the same operation as publishing, since the reviewer's decision *is* the publish action, per the design spec.)

- [ ] **Step 3: Add `sendPromptBackToDraft`**

In `src/admin.js`, add this function immediately after `submitPromptForReview` (added in Task 2, Step 3):

```js
async function sendPromptBackToDraft(promptId) {
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte skicka tillbaka förslag.', true);
    return;
  }

  const note = window.prompt('Kommentar till redaktören (valfritt):') || '';
  const reviewNote = note.trim() || 'Behöver justeras innan publicering.';

  const { error } = await supabase
    .from('content_items')
    .update({ status: 'draft', review_note: reviewNote })
    .eq('id', promptId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setErrorStatus(error, 'Kunde inte skicka tillbaka prompten.');
    return;
  }

  setStatus('Prompten skickades tillbaka till utkast.');
  await loadPrompts();
}
```

- [ ] **Step 4: Wire the click handler**

In `src/admin.js`, in the same destructuring block from Task 2 Step 4, add:

```js
  const sendBackButton = event.target.closest('[data-send-back-prompt]');
```

And near the other `if (...Button) { ... }` blocks, add:

```js
  if (sendBackButton) {
    sendPromptBackToDraft(sendBackButton.dataset.sendBackPrompt);
  }
```

- [ ] **Step 5: Verify**

```bash
node --input-type=module --check < src/admin.js
npm run build
```
Expected: both succeed with no errors.

Temp-disable technique: mock `state.prompts` with one item at `status: 'review'` and `state.profile.role = 'workspace_admin'`, call `renderPrompts()`, confirm the review list shows "Visa", "Godkänn & publicera", and "Skicka tillbaka" buttons, and that clicking "Visa" (via `document.querySelector('[data-preview-prompt]').click()` in the console, since you can't truly click through the temp-disabled page interactively without the real handler — or just manually flip `state.expandedPromptId` and re-call `renderPrompts()`) shows the prompt content in a `.mp-template-preview` div. Revert `admin.html` before committing.

- [ ] **Step 6: Commit**

```bash
git add src/admin.js
git commit -m "Let admins preview and approve or send back review submissions"
```

---

### Task 4: Add "Kort beskrivning" to the quick-create form

**Files:**
- Modify: `src/admin.js:1284-1301` (`renderWorkspaces` — the `data-quick-create-form` markup)
- Modify: `src/admin.js` (`submitQuickCreatePrompt`, currently lines 1327-1364)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Add the field to the form markup**

In `src/admin.js`, find this exact block (currently lines 1285-1301):

```js
        <form class="workspace-form compact" data-quick-create-form data-workspace-id="${w.id}">
          <label>Titel
            <input name="title" required minlength="2">
          </label>
          <label>Synlighet
            <select name="visibility">
              <option value="private">Privat</option>
              <option value="workspace">Delad med ytan</option>
            </select>
          </label>
          <label class="workspace-form-wide">Prompttext
            <textarea name="content" rows="3" required minlength="10"></textarea>
          </label>
          <div class="workspace-form-actions">
            <button type="submit">Spara utkast</button>
          </div>
        </form>
```

Replace with:

```js
        <form class="workspace-form compact" data-quick-create-form data-workspace-id="${w.id}">
          <label>Titel
            <input name="title" required minlength="2">
          </label>
          <label>Kort beskrivning
            <input name="summary" maxlength="140" placeholder="En rad om vad prompten gör">
          </label>
          <label>Synlighet
            <select name="visibility">
              <option value="private">Privat</option>
              <option value="workspace">Delad med ytan</option>
            </select>
          </label>
          <label class="workspace-form-wide">Prompttext
            <textarea name="content" rows="3" required minlength="10"></textarea>
          </label>
          <div class="workspace-form-actions">
            <button type="submit">Spara utkast</button>
          </div>
        </form>
```

- [ ] **Step 2: Send the field in `submitQuickCreatePrompt`**

In `src/admin.js`, find this exact block (currently around lines 1327-1350):

```js
async function submitQuickCreatePrompt(event) {
  event.preventDefault();
  const form = event.target;
  const workspaceId = form.dataset.workspaceId;
  const formData = new FormData(form);
  const title = formData.get('title')?.toString().trim();
  const content = formData.get('content')?.toString().trim();
  const visibility = formData.get('visibility')?.toString() || 'private';

  if (!title || !content) {
    setStatus('Titel och prompttext krävs.', true);
    return;
  }

  const { error } = await supabase.from('content_items').insert({
    workspace_id: workspaceId,
    type: 'prompt',
    title,
    slug: slugify(title),
    content,
    visibility,
    status: 'draft',
    created_by: state.user.id
  });
```

Replace with:

```js
async function submitQuickCreatePrompt(event) {
  event.preventDefault();
  const form = event.target;
  const workspaceId = form.dataset.workspaceId;
  const formData = new FormData(form);
  const title = formData.get('title')?.toString().trim();
  const summary = formData.get('summary')?.toString().trim() || null;
  const content = formData.get('content')?.toString().trim();
  const visibility = formData.get('visibility')?.toString() || 'private';

  if (!title || !content) {
    setStatus('Titel och prompttext krävs.', true);
    return;
  }

  const { error } = await supabase.from('content_items').insert({
    workspace_id: workspaceId,
    type: 'prompt',
    title,
    slug: slugify(title),
    summary,
    content,
    visibility,
    status: 'draft',
    created_by: state.user.id
  });
```

- [ ] **Step 3: Verify**

```bash
node --input-type=module --check < src/admin.js
npm run build
```
Expected: both succeed with no errors.

Temp-disable technique: mock `state.workspacesList` with one organization workspace, set `state.expandedWorkspaceId` to its id, call `renderWorkspaces()`, confirm the "Kort beskrivning" field renders between Titel and Synlighet with the placeholder text visible. Revert `admin.html` before committing.

- [ ] **Step 4: Commit**

```bash
git add src/admin.js
git commit -m "Add a short-description field to the quick-create prompt form"
```

---

### Task 5: Live role explanation on the workspace-card invite form

**Files:**
- Modify: `src/admin.js:1303-1322` (`renderWorkspaces` — the `data-workspace-invite-form` markup)
- Modify: `src/admin.js` (add a `querySelectorAll` wiring block at the end of `renderWorkspaces`)

**Interfaces:**
- Consumes: existing `roleLabels` dict (`src/admin.js:4-10`) — do not modify its text.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Add the hint element and `data-invite-role-select` attribute**

In `src/admin.js`, find this exact block (currently lines 1303-1322):

```js
      ${canInvite && state.expandedInviteWorkspaceId === w.id ? `
      <div class="mp-quick-create">
        <form class="workspace-form compact" data-workspace-invite-form data-workspace-id="${w.id}">
          <label>E-post
            <input type="email" name="email" required placeholder="kollega@exempel.se">
          </label>
          <label>Roll
            <select name="role">
              <option value="editor">Redigerare</option>
              <option value="viewer">Läsare</option>
              <option value="workspace_admin">Administratör</option>
            </select>
          </label>
          <div class="workspace-form-actions">
            <button type="submit">Bjud in till ${escapeHtml(w.name)}</button>
          </div>
        </form>
        <p class="mp-hint">Personen måste redan ha ett Promptbanken-konto${w.type === 'organization' && w.plan === 'start' ? ' och en egen aktiv Pro-plan' : ''}.</p>
        ${inviteStatus ? `<p class="mp-hint${inviteStatus.isError ? ' is-error' : ''}">${escapeHtml(inviteStatus.message)}</p>` : ''}
      </div>` : ''}
```

Replace with:

```js
      ${canInvite && state.expandedInviteWorkspaceId === w.id ? `
      <div class="mp-quick-create">
        <form class="workspace-form compact" data-workspace-invite-form data-workspace-id="${w.id}">
          <label>E-post
            <input type="email" name="email" required placeholder="kollega@exempel.se">
          </label>
          <label>Roll
            <select name="role" data-invite-role-select>
              <option value="editor">Redigerare</option>
              <option value="viewer">Läsare</option>
              <option value="workspace_admin">Administratör</option>
            </select>
          </label>
          <p class="mp-hint" data-invite-role-hint>${escapeHtml(roleLabels.editor)}</p>
          <div class="workspace-form-actions">
            <button type="submit">Bjud in till ${escapeHtml(w.name)}</button>
          </div>
        </form>
        <p class="mp-hint">Personen måste redan ha ett Promptbanken-konto${w.type === 'organization' && w.plan === 'start' ? ' och en egen aktiv Pro-plan' : ''}.</p>
        ${inviteStatus ? `<p class="mp-hint${inviteStatus.isError ? ' is-error' : ''}">${escapeHtml(inviteStatus.message)}</p>` : ''}
      </div>` : ''}
```

(`roleLabels.editor` is used as the pre-filled hint text because `editor` is the `<select>`'s first/default `<option>`.)

- [ ] **Step 2: Wire the live update**

In `src/admin.js`, find the end of `renderWorkspaces` — the closing of the function, currently:

```js
      </div>` : ''}
    `;
  }).join('');
}
```

Replace with:

```js
      </div>` : ''}
    `;
  }).join('');

  list.querySelectorAll('[data-invite-role-select]').forEach((select) => {
    const hint = select.closest('form')?.querySelector('[data-invite-role-hint]');
    if (!hint) return;
    select.addEventListener('change', () => {
      hint.textContent = roleLabels[select.value] || '';
    });
  });
}
```

- [ ] **Step 3: Verify**

```bash
node --input-type=module --check < src/admin.js
npm run build
```
Expected: both succeed with no errors.

Temp-disable technique: mock `state.workspacesList` with one organization workspace where `myRole: 'workspace_admin'`, set `state.expandedInviteWorkspaceId` to its id, call `renderWorkspaces()`, confirm the hint text shows `roleLabels.editor`'s exact string ("Skapa och redigera egna prompts.") under the role select by default, then in the console change the select's value to `workspace_admin` and dispatch a `change` event (`select.value = 'workspace_admin'; select.dispatchEvent(new Event('change'))`) and confirm the hint text updates to `roleLabels.workspace_admin`'s string. Revert `admin.html` before committing.

- [ ] **Step 4: Commit**

```bash
git add src/admin.js
git commit -m "Show a live role description on the invite-a-colleague form"
```

---

## Self-Review

**1. Spec coverage** — walking `docs/superpowers/specs/2026-07-11-review-flow-design.md` section by section:
- Del 1 (migration, statusövergångar, redaktörens vy, granskarens vy, nya funktioner) → Tasks 1, 2, 3. Covered.
- Del 2 (Kort beskrivning i snabbskapa-formuläret; huvudformuläret redan klart, ingen ändring där) → Task 4. Covered.
- Del 3 (rollinfo på arbetsyte-kortets bjud-in-formulär) → Task 5. Covered.
- Avgränsning (ingen ny roll, ingen historik, ingen e-post, inget kategori-fält) → correctly not built anywhere in Tasks 1-5.

**2. Placeholder scan** — every step above contains exact code, exact file:line locations, and exact verification commands with expected output; no "TODO"/"handle appropriately"/"similar to Task N" placeholders.

**3. Type/name consistency check** — `submitPromptForReview(promptId)` (Task 2) and `sendPromptBackToDraft(promptId)` (Task 3) both take a single string `promptId` argument and follow the exact same body shape as the pre-existing `publishPrompt`/`unpublishPrompt`, confirmed consistent between their definitions (Task 2 Step 3, Task 3 Step 3) and their call sites (Task 2 Step 4, Task 3 Step 4). `review_note` is spelled identically in the migration (Task 1), the `loadPrompts` select list (Task 2 Step 1), the card-list read (Task 2 Step 2), and both write sites (Task 2 Step 3, Task 3 Step 3). `data-invite-role-select` / `data-invite-role-hint` attribute names match between the markup (Task 5 Step 1) and the query selectors (Task 5 Step 2).

---

## Task Ordering Note

Tasks 2 and 3 both touch `renderPrompts()` but at disjoint line ranges (the "Mina prompts" card block vs. the review-list block) and disjoint new functions — they can be implemented in either order, but Task 2 is listed first because Task 3's Step 2 replacement block's surrounding context (the unchanged `reviewList.innerHTML = ...` ternary shape) is easier to diff against a file that hasn't already had Task 3's own edit applied twice. Tasks 4 and 5 are fully independent of 1-3 and of each other (different, non-overlapping line ranges in `renderWorkspaces`) and could run in parallel if using a workflow that supports it — this plan lists them sequentially for the default subagent-driven flow, which the project's instructions say runs one implementer at a time.
