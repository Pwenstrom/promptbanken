import { requireSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const roleLabels = {
  viewer: 'Läsa publicerade prompts i workspacen.',
  editor: 'Skapa och redigera egna prompts.',
  workspace_admin: 'Publicera och administrera organisationens prompts.',
  workspace_owner: 'Äga workspace-inställningar och publiceringsflöden.',
  platform_owner: 'Skapa publika Promptbanken-prompts och administrera plattformen.'
};

const state = {
  user: null,
  profile: null,
  workspace: null,
  prompts: [],
  members: [],
  apiKeys: [],
  mcpKeys: [],
  proInvites: [],
  joinCodes: [],
  editingPromptId: null,
  myPromptsSearch: '',
  expandedPromptId: null,
  formIsDirty: false
};

const riskLabels = {
  low: 'Låg risk',
  medium: 'Medelrisk',
  high: 'Hög risk'
};

const statusElement = document.querySelector('[data-admin-status]');
const dashboardElement = document.querySelector('[data-admin-dashboard]');
const noProfileElement = document.querySelector('[data-no-profile]');
const logoutButton = document.querySelector('[data-logout]');
const promptForm = document.querySelector('[data-prompt-form]');
const apiKeyForm = document.querySelector('[data-api-key-form]');
const mcpKeyForm = document.querySelector('[data-mcp-key-form]');
const inviteForm = document.querySelector('[data-invite-form]');
const promoteAdminForm = document.querySelector('[data-promote-admin-form]');
const inviteMemberForm = document.querySelector('[data-invite-member-form]');
const myPromptsSearchInput = document.querySelector('[data-my-prompts-search]');
const refreshButtons = document.querySelectorAll('[data-refresh]');
const visibilitySelect = promptForm?.querySelector('select[name="visibility"]');
const promptFormSubmit = promptForm?.querySelector('[data-prompt-form-submit]');
const promptFormCancel = promptForm?.querySelector('[data-prompt-form-cancel]');

function isAdminRole(role) {
  return ['workspace_admin', 'workspace_owner', 'platform_owner'].includes(role);
}

function isPlatformOwner() {
  return state.profile?.role === 'platform_owner';
}

function canEdit(role) {
  return ['editor', 'workspace_admin', 'workspace_owner', 'platform_owner'].includes(role);
}

function isPersonalFreeWorkspace() {
  return state.workspace?.type === 'personal' && state.workspace?.plan === 'free';
}

function isPlanPro() {
  return state.workspace?.plan === 'pro';
}

function apiEnabled() {
  return state.workspace?.api_enabled === true;
}

function mcpEnabled() {
  return state.workspace?.mcp_enabled === true;
}

function maxPrompts() {
  return state.workspace?.max_prompts ?? 3;
}

function mcpKeyLimit() {
  return isPlanPro() ? 5 : 1;
}

function allowedVisibilityOptions() {
  if (isPlatformOwner()) {
    return [
      ['private', 'Privat'],
      ['workspace', 'Organisation/workspace'],
      ['public', 'Publik i Promptbanken']
    ];
  }

  if (state.workspace?.type === 'organization') {
    return [['workspace', 'Organisationen']];
  }

  return [['private', 'Privat']];
}

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

function setText(selector, value) {
  document.querySelectorAll(selector).forEach((element) => {
    element.textContent = value === undefined || value === null || value === '' ? '-' : value;
  });
}

function showSecret(name, rawKey) {
  const panel = document.querySelector(`[data-new-${name}-panel]`);
  setText(`[data-new-${name}]`, rawKey);
  if (panel) panel.hidden = false;
}

function setFieldError(fieldName, message) {
  const input = promptForm?.querySelector(`[name="${fieldName}"]`);
  const errorEl = promptForm?.querySelector(`[data-field-error="${fieldName}"]`);
  if (input) input.classList.toggle('is-invalid', Boolean(message));
  if (errorEl) {
    errorEl.textContent = message || '';
    errorEl.hidden = !message;
  }
}

function clearFieldErrors() {
  promptForm?.querySelectorAll('[data-field-error]').forEach((el) => {
    el.hidden = true;
    el.textContent = '';
  });
  promptForm?.querySelectorAll('.is-invalid').forEach((el) => el.classList.remove('is-invalid'));
}

function validatePromptForm({ title, content }) {
  clearFieldErrors();
  let isValid = true;

  if (!title || title.length < 2) {
    setFieldError('title', 'Titel krävs (minst 2 tecken).');
    isValid = false;
  }

  if (!content || content.length < 10) {
    setFieldError('content', 'Prompttext krävs (minst 10 tecken).');
    isValid = false;
  }

  return isValid;
}

function emptyRow(colspan, text) {
  return `<tr><td colspan="${colspan}">${text}</td></tr>`;
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function slugify(value) {
  const base = (value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/å/g, 'a')
    .replace(/ä/g, 'a')
    .replace(/ö/g, 'o')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 90);

  // content_items_slug_format requires at least 3 chars, starting and
  // ending alphanumeric -- short titles (e.g. "AI") or titles made up
  // only of stripped characters would otherwise violate that constraint.
  if (base.length >= 3) {
    return base;
  }

  const suffix = Math.random().toString(36).slice(2, 8);
  return base ? `${base}-${suffix}` : `prompt-${suffix}`;
}

function renderRoleMode(role) {
  const modeElements = document.querySelectorAll('[data-role-mode]');
  modeElements.forEach((element) => {
    element.hidden = element.dataset.roleMode !== role;
  });

  setText('[data-role-summary]', roleLabels[role] || 'Roll utan särskilt dashboardläge.');
}

function renderCapabilityState() {
  document.querySelectorAll('[data-can-edit]').forEach((element) => {
    element.hidden = !canEdit(state.profile.role);
  });
  document.querySelectorAll('[data-admin-only]').forEach((element) => {
    element.hidden = !isAdminRole(state.profile.role);
  });

  document.querySelectorAll('[data-org-only]').forEach((element) => {
    element.hidden = state.workspace.type !== 'organization' && !isPlatformOwner();
  });

  document.querySelectorAll('[data-platform-only]').forEach((element) => {
    element.hidden = !isPlatformOwner();
  });

  const apiLocked = document.querySelector('[data-api-locked]');
  const apiUnlocked = document.querySelector('[data-api-unlocked]');
  if (apiLocked) apiLocked.hidden = apiEnabled();
  if (apiUnlocked) apiUnlocked.hidden = !apiEnabled();

  setText('[data-mcp-key-limit]', mcpKeyLimit());

  const mcpLocked = document.querySelector('[data-mcp-locked]');
  const mcpUnlocked = document.querySelector('[data-mcp-unlocked]');
  if (mcpLocked) mcpLocked.hidden = mcpEnabled();
  if (mcpUnlocked) mcpUnlocked.hidden = !mcpEnabled();
}

function renderPlanExpiry() {
  const element = document.querySelector('[data-plan-expiry]');
  if (!element) return;

  const expiresAt = state.workspace?.plan_expires_at;
  if (!expiresAt || state.workspace?.plan === 'free') {
    element.hidden = true;
    element.classList.remove('is-expiring-soon');
    return;
  }

  const daysLeft = Math.ceil((new Date(expiresAt).getTime() - Date.now()) / (24 * 60 * 60 * 1000));
  const dateLabel = new Date(expiresAt).toLocaleDateString('sv-SE');
  const sourceLabel = state.workspace?.plan_source === 'invite' ? 'Pro-test' : 'Pro-abonnemang';

  if (daysLeft > 1) {
    element.textContent = `${sourceLabel}: ${daysLeft} dagar kvar (till ${dateLabel})`;
  } else if (daysLeft === 1) {
    element.textContent = `${sourceLabel}: går ut imorgon (${dateLabel})`;
  } else if (daysLeft === 0) {
    element.textContent = `${sourceLabel}: går ut idag`;
  } else {
    element.textContent = `${sourceLabel}: perioden har gått ut, väntar på nedgradering till Free`;
  }

  element.hidden = false;
  element.classList.toggle('is-expiring-soon', daysLeft <= 7);
}

function renderPlanInfo() {
  const plan = state.workspace?.plan ?? 'free';
  const planLabels = { free: 'Free', pro: 'Pro', start: 'Start', plus: 'Plus', enterprise: 'Enterprise' };
  const badge = document.querySelector('[data-plan-badge]');
  const desc = document.querySelector('[data-plan-badge-desc]');
  const featureList = document.querySelector('[data-plan-feature-list]');
  const maxP = maxPrompts();

  if (badge) {
    badge.textContent = planLabels[plan] ?? plan;
    badge.dataset.plan = plan;
  }
  if (desc) {
    desc.textContent = 'Personligt konto';
  }

  renderPlanExpiry();

  const features = [
    { label: `${maxP} prompts`, ok: true },
    { label: 'MCP-nyckel (egna + publika prompts)', ok: true },
    { label: 'API-nycklar för externa integrationer', ok: apiEnabled() },
    { label: 'Dela prompts inom workspace', ok: isPlanPro() }
  ];

  if (featureList) {
    featureList.innerHTML = features.map(({ label, ok }) =>
      `<li class="${ok ? 'plan-feature-on' : 'plan-feature-off'}">${ok ? '✓' : '✗'} ${escapeHtml(label)}</li>`
    ).join('');
  }

  const maxEl = document.querySelector('[data-plan-max-prompts]');
  if (maxEl) maxEl.textContent = maxP;
}

function renderPromptFormRules() {
  if (!visibilitySelect) {
    return;
  }

  visibilitySelect.innerHTML = allowedVisibilityOptions()
    .map(([value, label]) => `<option value="${value}">${label}</option>`)
    .join('');

  if (isPersonalFreeWorkspace()) {
    setText('[data-prompt-limit-note]', 'Free-läge: du kan skapa upp till 3 privata prompts.');
  } else if (state.workspace.type === 'organization') {
    setText('[data-prompt-limit-note]', 'Organisationsläge: prompts sparas för den här organisationen.');
  } else {
    setText('[data-prompt-limit-note]', 'Platform-läge: du kan även skapa publika prompts till Promptbanken.');
  }
}

function renderPromptCounter(ownActivePrompts) {
  const note = document.querySelector('[data-prompt-count-note]');
  if (!note) return;

  const limit = maxPrompts();
  note.hidden = false;
  note.textContent = `${ownActivePrompts} av ${limit} prompts använda`;
  note.classList.toggle('is-at-limit', ownActivePrompts >= limit);
}

function renderPrompts() {
  const mineBody = document.querySelector('[data-my-prompts]');
  const libraryBody = document.querySelector('[data-library-prompts]');
  const reviewList = document.querySelector('[data-review-prompts]');
  const allOwnPrompts = state.prompts.filter((item) => item.owner_user_id === state.user.id || item.created_by === state.user.id);
  const publishedPrompts = state.prompts.filter((item) => item.status === 'published');
  const reviewPrompts = state.prompts.filter((item) => item.status !== 'published').slice(0, 6);
  const ownActivePrompts = allOwnPrompts.filter((item) => item.status !== 'archived').length;

  renderPromptCounter(ownActivePrompts);

  const search = state.myPromptsSearch.trim().toLowerCase();
  const ownPrompts = search
    ? allOwnPrompts.filter((item) => (
        item.title.toLowerCase().includes(search) || (item.category || '').toLowerCase().includes(search)
      ))
    : allOwnPrompts;

  if (!allOwnPrompts.length) {
    mineBody.innerHTML = emptyRow(6, 'Du har inga prompts än. Fyll i formuläret ovan för att skapa din första!');
  } else if (!ownPrompts.length) {
    mineBody.innerHTML = emptyRow(6, `Inga prompts matchar "${escapeHtml(state.myPromptsSearch)}".`);
  } else {
    mineBody.innerHTML = ownPrompts.map((item) => `
        <tr>
          <td>${escapeHtml(item.title)}</td>
          <td>${escapeHtml(item.status)}</td>
          <td>${escapeHtml(item.visibility)}</td>
          <td>${escapeHtml(riskLabels[item.risk_level] || riskLabels.low)}</td>
          <td>${escapeHtml(item.updated_at ? new Date(item.updated_at).toLocaleDateString('sv-SE') : '')}</td>
          <td>
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
          </td>
        </tr>
        ${state.expandedPromptId === item.id ? `
        <tr class="prompt-preview-row">
          <td colspan="6">${escapeHtml(item.content)}</td>
        </tr>` : ''}
      `).join('');
  }

  const canManageLibrary = isAdminRole(state.profile.role);
  libraryBody.innerHTML = publishedPrompts.length
    ? publishedPrompts.map((item) => `
        <tr>
          <td>${escapeHtml(item.title)}</td>
          <td>${escapeHtml(item.visibility)}</td>
          <td>${escapeHtml(item.category || '-')}</td>
          <td>${escapeHtml(item.audience || '-')}</td>
          <td>${escapeHtml(item.published_at ? new Date(item.published_at).toLocaleDateString('sv-SE') : '')}</td>
          ${canManageLibrary ? `
          <td>
            <button type="button" data-unpublish-prompt="${item.id}">Avpublicera</button>
            <button type="button" data-delete-prompt="${item.id}" data-delete-confirm="0">Ta bort</button>
          </td>` : ''}
        </tr>
      `).join('')
    : emptyRow(canManageLibrary ? 6 : 5, 'Inga publicerade prompts i biblioteket ännu.');
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

  renderAdminMetrics();
  setText('[data-admin-stat="ownPrompts"]', ownActivePrompts);
  setText('[data-free-prompts-used]', ownActivePrompts);
}

function renderAdminMetrics() {
  const published = state.prompts.filter((item) => item.status === 'published').length;
  const drafts = state.prompts.filter((item) => item.status === 'draft').length;
  const review = state.prompts.filter((item) => item.status !== 'published').length;
  setText('[data-admin-stat="published"]', published);
  setText('[data-admin-stat="review"]', review);
  setText('[data-admin-stat="drafts"]', drafts);
  setText('[data-admin-stat="members"]', state.members.length);
}

async function ensurePersonalWorkspace() {
  const { error } = await supabase.rpc('ensure_personal_workspace');
  if (error) {
    throw error;
  }
}

function renderMembers() {
  const body = document.querySelector('[data-members]');
  body.innerHTML = state.members.length
    ? state.members.map((member) => `
        <tr>
          <td>${escapeHtml(member.user_id)}</td>
          <td>${escapeHtml(member.role)}</td>
          <td>${escapeHtml(member.created_at ? new Date(member.created_at).toLocaleDateString('sv-SE') : '')}</td>
        </tr>
      `).join('')
    : emptyRow(3, 'Inga medlemmar synliga med din roll.');
  renderAdminMetrics();
}

function renderJoinCodes() {
  const body = document.querySelector('[data-join-codes]');
  if (!body) return;
  body.innerHTML = state.joinCodes.length
    ? state.joinCodes.map((code) => `
        <tr>
          <td>${escapeHtml(code.role)}</td>
          <td>${escapeHtml(code.status === 'active' ? 'Aktiv' : 'Återkallad')}</td>
          <td>${escapeHtml(code.created_at ? new Date(code.created_at).toLocaleDateString('sv-SE') : '')}</td>
          <td>
            ${code.status === 'active' ? `<button type="button" data-revoke-join-code="${code.id}">Återkalla</button>` : ''}
          </td>
        </tr>
      `).join('')
    : emptyRow(4, 'Ingen join-länk skapad ännu.');
}

function renderApiKeys() {
  const body = document.querySelector('[data-api-keys]');
  body.innerHTML = state.apiKeys.length
    ? state.apiKeys.map((key) => `
        <tr>
          <td>${escapeHtml(key.name)}</td>
          <td><code>${escapeHtml(key.key_prefix)}</code></td>
          <td>${escapeHtml((key.scopes || []).join(', ') || '-')}</td>
          <td>${escapeHtml(key.revoked_at ? 'Återkallad' : 'Aktiv')}</td>
          <td>${escapeHtml(key.created_at ? new Date(key.created_at).toLocaleDateString('sv-SE') : '')}</td>
          <td>
            ${!key.revoked_at ? `<button type="button" data-revoke-api-key="${key.id}">Återkalla</button>` : ''}
          </td>
        </tr>
      `).join('')
    : emptyRow(6, 'Inga API-nycklar ännu.');
}

function renderMcpKeys() {
  const body = document.querySelector('[data-mcp-keys]');
  if (!body) return;
  body.innerHTML = state.mcpKeys.length
    ? state.mcpKeys.map((key) => `
        <tr>
          <td>${escapeHtml(key.name)}</td>
          <td><code>${escapeHtml(key.key_prefix)}</code></td>
          <td>${escapeHtml(key.revoked_at ? 'Återkallad' : 'Aktiv')}</td>
          <td>${escapeHtml(key.created_at ? new Date(key.created_at).toLocaleDateString('sv-SE') : '')}</td>
          <td>
            ${!key.revoked_at ? `<button type="button" data-revoke-mcp-key="${key.id}">Återkalla</button>` : ''}
          </td>
        </tr>
      `).join('')
    : emptyRow(5, 'Ingen MCP-nyckel skapad ännu.');
}

function renderProInvites() {
  const body = document.querySelector('[data-pro-invites]');
  if (!body) return;
  body.innerHTML = state.proInvites.length
    ? state.proInvites.map((invite) => `
        <tr>
          <td><code>${escapeHtml(invite.token)}</code></td>
          <td>${escapeHtml(invite.note || '-')}</td>
          <td>${escapeHtml(invite.days)}</td>
          <td>${escapeHtml(invite.status)}</td>
          <td>${escapeHtml(invite.created_at ? new Date(invite.created_at).toLocaleDateString('sv-SE') : '')}</td>
          <td>${escapeHtml(invite.expires_at ? new Date(invite.expires_at).toLocaleDateString('sv-SE') : '')}</td>
        </tr>
      `).join('')
    : emptyRow(6, 'Ingen inbjudan skapad ännu.');
}

async function loadMcpKeys() {
  if (!isAdminRole(state.profile.role)) {
    state.mcpKeys = [];
    renderMcpKeys();
    return;
  }

  const { data, error } = await supabase
    .from('api_keys')
    .select('id, name, key_prefix, scopes, revoked_at, created_at')
    .eq('workspace_id', state.workspace.id)
    .contains('scopes', ['mcp'])
    .order('created_at', { ascending: false });

  if (error) throw error;
  state.mcpKeys = data || [];
  renderMcpKeys();
}

async function createMcpKey(event) {
  event.preventDefault();
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte skapa MCP-nycklar.', true);
    return;
  }
  if (!mcpEnabled()) {
    setStatus('MCP är inte aktiverat för det här workspacet.', true);
    return;
  }

  const formData = new FormData(mcpKeyForm);
  const name = formData.get('name')?.toString().trim();
  if (!name) {
    setStatus('Namn krävs för MCP-nyckeln.', true);
    return;
  }

  const activeCount = state.mcpKeys.filter((k) => !k.revoked_at).length;
  const keyLimit = mcpKeyLimit();
  if (activeCount >= keyLimit && state.workspace?.type === 'personal') {
    setStatus(`Du har nått gränsen på ${keyLimit} aktiva MCP-nyckel(ar) för din plan. Återkalla en befintlig för att skapa en ny.`, true);
    return;
  }

  const rawKey = `pb_mcp_${randomToken()}`;
  const keyPrefix = rawKey.slice(0, 16);
  const keyHash = await sha256Hex(rawKey);

  const { error } = await supabase.from('api_keys').insert({
    workspace_id: state.workspace.id,
    created_by: state.user.id,
    name,
    key_prefix: keyPrefix,
    key_hash: keyHash,
    scopes: ['mcp']
  });

  if (error) {
    setStatus(error.message || 'Kunde inte skapa MCP-nyckel.', true);
    return;
  }

  mcpKeyForm.reset();
  showSecret('mcp-key', rawKey);
  setStatus('MCP-nyckeln skapades. Kopiera den nu, den visas bara en gång.');
  await loadMcpKeys();
}

async function revokeMcpKey(keyId) {
  const { error } = await supabase
    .from('api_keys')
    .update({ revoked_at: new Date().toISOString() })
    .eq('id', keyId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setStatus(error.message || 'Kunde inte återkalla MCP-nyckel.', true);
    return;
  }

  setStatus('MCP-nyckeln återkallades.');
  await loadMcpKeys();
}

async function loadProfile(user) {
  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id, role, workspace_id')
    .eq('user_id', user.id)
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle();

  if (profileError) {
    throw profileError;
  }

  if (!profile) {
    await ensurePersonalWorkspace();
    return loadProfile(user);
  }

  const { data: workspace, error: workspaceError } = await supabase
    .from('workspaces')
    .select('id, name, type, plan, api_enabled, mcp_enabled, max_prompts, plan_source, plan_expires_at')
    .eq('id', profile.workspace_id)
    .single();

  if (workspaceError) {
    throw workspaceError;
  }

  state.user = user;
  state.profile = profile;
  state.workspace = workspace;

  setText('[data-user-email]', user.email);
  setText('[data-workspace-name]', workspace.name);
  setText('[data-workspace-type]', workspace.type);
  setText('[data-workspace-plan]', workspace.plan);
  setText('[data-profile-role]', profile.role);
  renderRoleMode(profile.role);
  renderCapabilityState();
  renderPromptFormRules();
  renderPlanInfo();

  dashboardElement.hidden = false;
  noProfileElement.hidden = true;
  setStatus('');
  return true;
}

async function loadPrompts() {
  const { data, error } = await supabase
    .from('content_items')
    .select('id, title, slug, summary, content, status, visibility, category, audience, risk_level, owner_user_id, created_by, published_at, updated_at')
    .eq('workspace_id', state.workspace.id)
    .order('updated_at', { ascending: false });

  if (error) {
    throw error;
  }

  state.prompts = data || [];
  renderPrompts();
}

async function loadMembers() {
  const { data, error } = await supabase
    .from('profiles')
    .select('user_id, role, created_at')
    .eq('workspace_id', state.workspace.id)
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  state.members = data || [];
  renderMembers();
}

async function loadJoinCodes() {
  if (state.workspace?.type !== 'organization' || !isAdminRole(state.profile.role)) {
    state.joinCodes = [];
    renderJoinCodes();
    return;
  }

  const { data, error } = await supabase
    .from('org_join_codes')
    .select('id, token, role, status, created_at')
    .eq('workspace_id', state.workspace.id)
    .order('created_at', { ascending: false });

  if (error) throw error;
  state.joinCodes = data || [];
  renderJoinCodes();
}

async function inviteOrgMember(event) {
  event.preventDefault();
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte bjuda in medlemmar.', true);
    return;
  }

  const formData = new FormData(inviteMemberForm);
  const email = formData.get('email')?.toString().trim();
  const role = formData.get('role')?.toString() || 'editor';

  if (!email) {
    setStatus('E-post krävs.', true);
    return;
  }

  const { error } = await supabase.rpc('invite_org_member', {
    p_workspace_id: state.workspace.id,
    p_email: email,
    p_role: role
  });

  if (error) {
    setStatus(error.message || 'Kunde inte bjuda in medlem.', true);
    return;
  }

  inviteMemberForm.reset();
  setStatus(`${email} har lagts till i workspacet.`);
  await loadMembers();
}

async function generateJoinCode() {
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte skapa join-länkar.', true);
    return;
  }

  const token = `team_${randomToken().slice(0, 24)}`;

  const { error } = await supabase.from('org_join_codes').insert({
    workspace_id: state.workspace.id,
    token,
    role: 'editor',
    created_by: state.user.id
  });

  if (error) {
    setStatus(error.message || 'Kunde inte skapa join-länk.', true);
    return;
  }

  showSecret('join-link', `${window.location.origin}/team-invite.html?team_token=${token}`);
  setStatus('Join-länk skapad. Kopiera och dela den med teamet.');
  await loadJoinCodes();
}

async function revokeJoinCode(codeId) {
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte återkalla join-länkar.', true);
    return;
  }

  const { error } = await supabase
    .from('org_join_codes')
    .update({ status: 'revoked' })
    .eq('id', codeId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setStatus(error.message || 'Kunde inte återkalla join-länken.', true);
    return;
  }

  setStatus('Join-länken återkallades.');
  await loadJoinCodes();
}

async function loadApiKeys() {
  if (!isAdminRole(state.profile.role)) {
    state.apiKeys = [];
    renderApiKeys();
    return;
  }

  const { data, error } = await supabase
    .from('api_keys')
    .select('id, name, key_prefix, scopes, last_used_at, revoked_at, created_at')
    .eq('workspace_id', state.workspace.id)
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  state.apiKeys = data || [];
  renderApiKeys();
}

async function refreshWorkspaceData() {
  setStatus('Uppdaterar...');
  await Promise.all([loadPrompts(), loadMembers(), loadJoinCodes(), loadMcpKeys(), loadApiKeys(), loadProInvites()]);
  setStatus('');
}

function startEditPrompt(promptId) {
  const item = state.prompts.find((p) => p.id === promptId);
  if (!item) return;

  state.editingPromptId = promptId;
  promptForm.querySelector('[name="title"]').value = item.title || '';
  promptForm.querySelector('[name="slug"]').value = item.slug || '';
  promptForm.querySelector('[name="visibility"]').value = item.visibility || 'private';
  promptForm.querySelector('[name="category"]').value = item.category || '';
  promptForm.querySelector('[name="audience"]').value = item.audience || '';
  promptForm.querySelector('[name="risk_level"]').value = item.risk_level || 'low';
  promptForm.querySelector('[name="summary"]').value = item.summary || '';
  promptForm.querySelector('[name="content"]').value = item.content || '';

  if (promptFormSubmit) promptFormSubmit.textContent = 'Spara ändringar';
  if (promptFormCancel) promptFormCancel.hidden = false;
  promptForm.scrollIntoView({ behavior: 'smooth', block: 'start' });
  state.formIsDirty = false;
}

function cancelEditPrompt() {
  state.editingPromptId = null;
  promptForm.reset();
  clearFieldErrors();
  if (promptFormSubmit) promptFormSubmit.textContent = 'Spara utkast';
  if (promptFormCancel) promptFormCancel.hidden = true;
  state.formIsDirty = false;
}

async function savePrompt(event) {
  event.preventDefault();

  if (!state.profile || !state.workspace) {
    setStatus('Workspace är inte laddat än. Vänta tills sidan laddat klart och försök igen.', true);
    return;
  }

  if (!canEdit(state.profile.role)) {
    setStatus('Din roll får inte skapa prompts.', true);
    return;
  }

  try {
    await savePromptUnsafe();
  } catch (error) {
    setStatus(error?.message || 'Kunde inte spara prompt (oväntat fel).', true);
  }
}

async function savePromptUnsafe() {
  const formData = new FormData(promptForm);
  const title = formData.get('title')?.toString().trim();
  const content = formData.get('content')?.toString().trim();
  const slug = slugify(formData.get('slug')?.toString().trim() || title);
  const riskLevel = formData.get('risk_level')?.toString() || 'low';
  let visibility = formData.get('visibility')?.toString() || 'private';

  if (!allowedVisibilityOptions().some(([value]) => value === visibility)) {
    visibility = allowedVisibilityOptions()[0][0];
  }

  if (!validatePromptForm({ title, content })) {
    setStatus('Rätta fälten som är markerade nedan.', true);
    return;
  }

  const editingId = state.editingPromptId;

  if (!editingId && state.workspace?.type === 'personal') {
    const activeOwnPrompts = state.prompts.filter((item) => (
      item.status !== 'archived'
      && (item.owner_user_id === state.user.id || item.created_by === state.user.id)
    )).length;
    const limit = maxPrompts();
    if (activeOwnPrompts >= limit) {
      setStatus(`Du har skapat max antal prompts (${limit} st). Ta bort en prompt eller uppgradera för att skapa fler.`, true);
      return;
    }
  }

  const payload = {
    title,
    slug,
    summary: formData.get('summary')?.toString().trim() || null,
    content,
    visibility,
    category: formData.get('category')?.toString().trim() || null,
    audience: formData.get('audience')?.toString().trim() || null,
    risk_level: riskLevel
  };

  const { error } = editingId
    ? await supabase.from('content_items').update(payload).eq('id', editingId)
    : await supabase.from('content_items').insert({
        ...payload,
        workspace_id: state.workspace.id,
        owner_user_id: state.user.id,
        type: 'prompt',
        status: 'draft',
        created_by: state.user.id
      });

  if (error) {
    setStatus(error.message || 'Kunde inte spara prompt.', true);
    return;
  }

  cancelEditPrompt();
  setStatus(editingId ? 'Prompten uppdaterades.' : 'Prompten sparades som utkast.');
  await loadPrompts();
}

function exportMyPrompts() {
  const ownPrompts = state.prompts.filter((item) => (
    item.owner_user_id === state.user.id || item.created_by === state.user.id
  ));

  if (!ownPrompts.length) {
    setStatus('Du har inga egna prompts att exportera än.', true);
    return;
  }

  const exportPayload = {
    exported_at: new Date().toISOString(),
    user_email: state.user.email,
    workspace: state.workspace.name,
    prompts: ownPrompts.map((item) => ({
      title: item.title,
      slug: item.slug,
      summary: item.summary,
      content: item.content,
      status: item.status,
      visibility: item.visibility,
      category: item.category,
      audience: item.audience,
      risk_level: item.risk_level,
      updated_at: item.updated_at
    }))
  };

  const blob = new Blob([JSON.stringify(exportPayload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `promptbanken-mina-prompts-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);

  setStatus(`Exporterade ${ownPrompts.length} prompt(s).`);
}

async function deletePrompt(promptId) {
  const { error } = await supabase
    .from('content_items')
    .delete()
    .eq('id', promptId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setStatus(error.message || 'Kunde inte ta bort prompt.', true);
    return;
  }

  if (state.editingPromptId === promptId) {
    cancelEditPrompt();
  }

  setStatus('Prompten togs bort.');
  await loadPrompts();
}

async function unpublishPrompt(promptId) {
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte avpublicera.', true);
    return;
  }

  const { error } = await supabase
    .from('content_items')
    .update({ status: 'draft' })
    .eq('id', promptId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setStatus(error.message || 'Kunde inte avpublicera prompt.', true);
    return;
  }

  setStatus('Prompten avpublicerades och är nu ett utkast.');
  await loadPrompts();
}

async function publishPrompt(promptId) {
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte publicera.', true);
    return;
  }

  const { error } = await supabase
    .from('content_items')
    .update({ status: 'published' })
    .eq('id', promptId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setStatus(error.message || 'Kunde inte publicera prompt.', true);
    return;
  }

  setStatus('Prompten publicerades.');
  await loadPrompts();
}

async function sha256Hex(value) {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function createApiKey(event) {
  event.preventDefault();
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte skapa API-nycklar.', true);
    return;
  }

  const formData = new FormData(apiKeyForm);
  const name = formData.get('name')?.toString().trim();
  if (!name) {
    setStatus('Namn krävs för API-nyckeln.', true);
    return;
  }

  const rawKey = `pb_${randomToken()}`;
  const keyPrefix = rawKey.slice(0, 12);
  const keyHash = await sha256Hex(rawKey);
  const scopes = formData.get('scopes')?.toString().split(',').map((scope) => scope.trim()).filter(Boolean) || ['read'];

  const { error } = await supabase.from('api_keys').insert({
    workspace_id: state.workspace.id,
    created_by: state.user.id,
    name,
    key_prefix: keyPrefix,
    key_hash: keyHash,
    scopes
  });

  if (error) {
    setStatus(error.message || 'Kunde inte skapa API-nyckel.', true);
    return;
  }

  apiKeyForm.reset();
  showSecret('api-key', rawKey);
  setStatus('API-nyckeln skapades. Kopiera den nu, den visas bara här.');
  await loadApiKeys();
}

async function loadProInvites() {
  if (!isPlatformOwner()) {
    state.proInvites = [];
    renderProInvites();
    return;
  }

  const { data, error } = await supabase
    .from('pro_invites')
    .select('id, token, note, plan, days, status, created_at, expires_at')
    .order('created_at', { ascending: false });

  if (error) throw error;
  state.proInvites = data || [];
  renderProInvites();
}

async function createProInvite(event) {
  event.preventDefault();
  if (!isPlatformOwner()) {
    setStatus('Endast plattformsadmin kan skapa Pro-inbjudningar.', true);
    return;
  }

  const formData = new FormData(inviteForm);
  const days = Number(formData.get('days')) || 30;
  const note = formData.get('note')?.toString().trim() || null;
  const token = `pro_${randomToken().slice(0, 24)}`;

  const { error } = await supabase.from('pro_invites').insert({
    token,
    plan: 'pro',
    days,
    note
  });

  if (error) {
    setStatus(error.message || 'Kunde inte skapa inbjudan.', true);
    return;
  }

  inviteForm.reset();
  inviteForm.querySelector('[name="days"]').value = 30;
  showSecret('invite-link', `${window.location.origin}/invite.html?token=${token}`);
  setStatus('Inbjudan skapades. Kopiera länken och skicka den till mottagaren.');
  await loadProInvites();
}

async function promoteAdmin(event) {
  event.preventDefault();
  if (!isPlatformOwner()) {
    setStatus('Endast plattformsadmin kan göra detta.', true);
    return;
  }

  const formData = new FormData(promoteAdminForm);
  const email = formData.get('email')?.toString().trim();
  if (!email) {
    setStatus('E-post krävs.', true);
    return;
  }

  const { error } = await supabase.rpc('promote_user_to_platform_owner', { p_email: email });

  if (error) {
    setStatus(error.message || 'Kunde inte göra användaren till admin.', true);
    return;
  }

  promoteAdminForm.reset();
  setStatus(`${email} är nu plattformsadmin.`);
}

async function deleteAccount() {
  const confirmed = window.confirm(
    'Radera ditt konto permanent? Ditt privata workspace och alla dina egna prompts tas bort och går inte att återfå. ' +
    'Har du redan exporterat dina prompts om du vill spara dem?'
  );
  if (!confirmed) {
    return;
  }

  setStatus('Raderar konto...');

  const { data: sessionData } = await supabase.auth.getSession();
  const accessToken = sessionData?.session?.access_token;
  if (!accessToken) {
    setStatus('Ingen giltig session hittades. Logga in igen och försök på nytt.', true);
    return;
  }

  const { data, error } = await supabase.functions.invoke('delete-account', {
    headers: { Authorization: `Bearer ${accessToken}` }
  });

  if (error) {
    const message = data?.error || error.message || 'Kunde inte radera kontot.';
    setStatus(message, true);
    return;
  }

  await supabase.auth.signOut();
  window.location.assign('login.html');
}

async function revokeApiKey(keyId) {
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte återkalla API-nycklar.', true);
    return;
  }

  const { error } = await supabase
    .from('api_keys')
    .update({ revoked_at: new Date().toISOString() })
    .eq('id', keyId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setStatus(error.message || 'Kunde inte återkalla API-nyckel.', true);
    return;
  }

  setStatus('API-nyckeln återkallades.');
  await loadApiKeys();
}

async function logout() {
  setStatus('Loggar ut...');
  const { error } = await supabase.auth.signOut();
  if (error && error.name !== 'AuthSessionMissingError') {
    setStatus(error.message || 'Kunde inte logga ut.', true);
  }

  // signOut() can bail out before clearing the local token (e.g. when it
  // first finds the session already invalid), leaving a stale token in
  // storage that bounces login.html straight back here. Clear it directly.
  Object.keys(window.localStorage)
    .filter((key) => /^sb-.*-auth-token$/.test(key))
    .forEach((key) => window.localStorage.removeItem(key));

  window.location.replace('login.html');
}

async function init() {
  if (!requireSupabaseConfig(statusElement)) {
    return;
  }

  const session = await requireSession();
  if (!session) {
    return;
  }

  setStatus('Laddar workspace...');
  const hasProfile = await loadProfile(session.user);
  if (hasProfile) {
    await refreshWorkspaceData();
  }
}

if (logoutButton) {
  logoutButton.addEventListener('click', logout);
}

if (promptForm) {
  promptForm.addEventListener('submit', savePrompt);
  promptForm.querySelectorAll('[name="title"], [name="content"]').forEach((field) => {
    field.addEventListener('input', () => setFieldError(field.name, ''));
  });
}

if (promptFormCancel) {
  promptFormCancel.addEventListener('click', cancelEditPrompt);
}

if (apiKeyForm) {
  apiKeyForm.addEventListener('submit', createApiKey);
}

if (mcpKeyForm) {
  mcpKeyForm.addEventListener('submit', createMcpKey);
}

if (inviteForm) {
  inviteForm.addEventListener('submit', createProInvite);
}

if (promoteAdminForm) {
  promoteAdminForm.addEventListener('submit', promoteAdmin);
}

if (inviteMemberForm) {
  inviteMemberForm.addEventListener('submit', inviteOrgMember);
}

const generateJoinCodeButton = document.querySelector('[data-generate-join-code]');
if (generateJoinCodeButton) {
  generateJoinCodeButton.addEventListener('click', generateJoinCode);
}

if (myPromptsSearchInput) {
  myPromptsSearchInput.addEventListener('input', () => {
    state.myPromptsSearch = myPromptsSearchInput.value;
    renderPrompts();
  });
}

if (promptForm) {
  promptForm.addEventListener('input', () => {
    state.formIsDirty = true;
  });
}

window.addEventListener('beforeunload', (event) => {
  if (state.formIsDirty) {
    event.preventDefault();
    event.returnValue = '';
  }
});

function switchIntegrationTab(panelId) {
  document.querySelectorAll('[data-integration-tab]').forEach((tab) => {
    const isActive = tab.dataset.integrationTab === panelId;
    tab.classList.toggle('active', isActive);
    tab.setAttribute('aria-selected', String(isActive));
  });
  document.querySelectorAll('[data-integration-panel]').forEach((panel) => {
    panel.hidden = panel.id !== panelId;
  });
}

function initIntegrationTabs() {
  document.querySelectorAll('[data-integration-tab]').forEach((tab) => {
    tab.addEventListener('click', () => switchIntegrationTab(tab.dataset.integrationTab));
  });

  document.querySelectorAll('a.admin-nav-link[href="#api-nycklar"], a.admin-nav-link[href="#mcp-nyckel"]').forEach((link) => {
    link.addEventListener('click', (event) => {
      event.preventDefault();
      const panelId = link.getAttribute('href').slice(1);
      switchIntegrationTab(panelId);
      document.getElementById(panelId)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });
}

initIntegrationTabs();

function initNavScrollSpy() {
  const navLinks = document.querySelectorAll('.admin-nav-link[href^="#"]');
  if (!navLinks.length) return;

  const sections = [...navLinks]
    .map((link) => document.getElementById(link.getAttribute('href').slice(1)))
    .filter(Boolean);

  if (!sections.length) return;

  const setActive = (id) => {
    navLinks.forEach((link) => {
      link.classList.toggle('active', link.getAttribute('href') === `#${id}`);
    });
  };

  const observer = new IntersectionObserver(
    (entries) => {
      const visible = entries.filter((entry) => entry.isIntersecting);
      if (visible.length) {
        setActive(visible[0].target.id);
      }
    },
    { rootMargin: '-96px 0px -70% 0px', threshold: 0 }
  );

  sections.forEach((section) => observer.observe(section));
}

initNavScrollSpy();

const exportMyPromptsButton = document.querySelector('[data-export-my-prompts]');
if (exportMyPromptsButton) {
  exportMyPromptsButton.addEventListener('click', exportMyPrompts);
}

const deleteAccountButton = document.querySelector('[data-delete-account]');
if (deleteAccountButton) {
  deleteAccountButton.addEventListener('click', deleteAccount);
}

refreshButtons.forEach((button) => {
  button.addEventListener('click', () => {
    refreshWorkspaceData().catch((error) => setStatus(error.message || 'Kunde inte uppdatera.', true));
  });
});

document.addEventListener('click', (event) => {
  const publishButton = event.target.closest('[data-publish-prompt]');
  const unpublishButton = event.target.closest('[data-unpublish-prompt]');
  const editButton = event.target.closest('[data-edit-prompt]');
  const deleteButton = event.target.closest('[data-delete-prompt]');
  const previewButton = event.target.closest('[data-preview-prompt]');
  const revokeButton = event.target.closest('[data-revoke-api-key]');

  const revokeMcpButton = event.target.closest('[data-revoke-mcp-key]');
  const revokeJoinCodeButton = event.target.closest('[data-revoke-join-code]');
  const copySecretButton = event.target.closest('[data-copy-secret]');

  if (publishButton) {
    publishPrompt(publishButton.dataset.publishPrompt);
  }

  if (unpublishButton) {
    unpublishPrompt(unpublishButton.dataset.unpublishPrompt);
  }

  if (editButton) {
    startEditPrompt(editButton.dataset.editPrompt);
  }

  if (deleteButton) {
    if (deleteButton.dataset.deleteConfirm === '1') {
      deletePrompt(deleteButton.dataset.deletePrompt);
    } else {
      deleteButton.dataset.deleteConfirm = '1';
      const originalLabel = deleteButton.textContent;
      deleteButton.textContent = 'Bekräfta radering?';
      deleteButton.classList.add('is-confirming');
      setTimeout(() => {
        if (deleteButton.isConnected) {
          deleteButton.dataset.deleteConfirm = '0';
          deleteButton.textContent = originalLabel;
          deleteButton.classList.remove('is-confirming');
        }
      }, 4000);
    }
  }

  if (previewButton) {
    const promptId = previewButton.dataset.previewPrompt;
    state.expandedPromptId = state.expandedPromptId === promptId ? null : promptId;
    renderPrompts();
  }

  if (revokeButton) {
    revokeApiKey(revokeButton.dataset.revokeApiKey);
  }

  if (revokeMcpButton) {
    revokeMcpKey(revokeMcpButton.dataset.revokeMcpKey);
  }

  if (revokeJoinCodeButton) {
    revokeJoinCode(revokeJoinCodeButton.dataset.revokeJoinCode);
  }

  if (copySecretButton) {
    const name = copySecretButton.dataset.copySecret;
    const value = document.querySelector(`[data-${name}]`)?.textContent;
    if (value) {
      const originalLabel = copySecretButton.textContent;
      navigator.clipboard.writeText(value)
        .then(() => {
          setStatus('Kopierad till urklipp.');
          copySecretButton.textContent = 'Kopierad!';
          copySecretButton.classList.add('is-copied');
          setTimeout(() => {
            copySecretButton.textContent = originalLabel;
            copySecretButton.classList.remove('is-copied');
          }, 2000);
        })
        .catch(() => setStatus('Kunde inte kopiera, markera och kopiera manuellt.', true));
    }
  }
});

init().catch((error) => {
  setStatus(error.message || 'Kunde inte ladda adminytan.', true);
});
