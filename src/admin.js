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
  editingPromptId: null
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
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/å/g, 'a')
    .replace(/ä/g, 'a')
    .replace(/ö/g, 'o')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 90);
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

  const mcpLocked = document.querySelector('[data-mcp-locked]');
  const mcpUnlocked = document.querySelector('[data-mcp-unlocked]');
  if (mcpLocked) mcpLocked.hidden = mcpEnabled();
  if (mcpUnlocked) mcpUnlocked.hidden = !mcpEnabled();
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

function renderPrompts() {
  const mineBody = document.querySelector('[data-my-prompts]');
  const libraryBody = document.querySelector('[data-library-prompts]');
  const reviewList = document.querySelector('[data-review-prompts]');
  const ownPrompts = state.prompts.filter((item) => item.owner_user_id === state.user.id || item.created_by === state.user.id);
  const publishedPrompts = state.prompts.filter((item) => item.status === 'published');
  const reviewPrompts = state.prompts.filter((item) => item.status !== 'published').slice(0, 6);
  const ownActivePrompts = ownPrompts.filter((item) => item.status !== 'archived').length;

  mineBody.innerHTML = ownPrompts.length
    ? ownPrompts.map((item) => `
        <tr>
          <td>${escapeHtml(item.title)}</td>
          <td>${escapeHtml(item.status)}</td>
          <td>${escapeHtml(item.visibility)}</td>
          <td>${escapeHtml(riskLabels[item.risk_level] || riskLabels.low)}</td>
          <td>${escapeHtml(item.updated_at ? new Date(item.updated_at).toLocaleDateString('sv-SE') : '')}</td>
          <td>
            ${item.status !== 'published'
              ? `<button type="button" data-edit-prompt="${item.id}">Redigera</button>`
              : ''}
            ${isAdminRole(state.profile.role) && item.status !== 'published'
              ? `<button type="button" data-publish-prompt="${item.id}">Publicera</button>`
              : ''}
            ${item.status !== 'published'
              ? `<button type="button" data-delete-prompt="${item.id}">Ta bort</button>`
              : ''}
          </td>
        </tr>
      `).join('')
    : emptyRow(6, 'Inga egna prompts ännu.');

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
            <button type="button" data-delete-prompt="${item.id}">Ta bort</button>
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
  if (activeCount >= 1 && state.workspace?.type === 'personal') {
    setStatus('Du har redan en aktiv MCP-nyckel. Återkalla den befintliga för att skapa en ny.', true);
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
    .select('id, name, type, plan, api_enabled, mcp_enabled, max_prompts')
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
  await Promise.all([loadPrompts(), loadMembers(), loadMcpKeys(), loadApiKeys()]);
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
}

function cancelEditPrompt() {
  state.editingPromptId = null;
  promptForm.reset();
  if (promptFormSubmit) promptFormSubmit.textContent = 'Spara utkast';
  if (promptFormCancel) promptFormCancel.hidden = true;
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

  if (!title || !content || !slug) {
    setStatus('Titel, slug och prompttext krävs.', true);
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
      const plan = state.workspace.plan ?? 'free';
      setStatus(`Du har nått gränsen på ${limit} prompts för ${plan}-planen.`, true);
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

async function deletePrompt(promptId) {
  if (!window.confirm('Ta bort den här prompten? Det går inte att ångra.')) {
    return;
  }

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
  const revokeButton = event.target.closest('[data-revoke-api-key]');

  const revokeMcpButton = event.target.closest('[data-revoke-mcp-key]');
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
    deletePrompt(deleteButton.dataset.deletePrompt);
  }

  if (revokeButton) {
    revokeApiKey(revokeButton.dataset.revokeApiKey);
  }

  if (revokeMcpButton) {
    revokeMcpKey(revokeMcpButton.dataset.revokeMcpKey);
  }

  if (copySecretButton) {
    const name = copySecretButton.dataset.copySecret;
    const value = document.querySelector(`[data-${name}]`)?.textContent;
    if (value) {
      navigator.clipboard.writeText(value)
        .then(() => setStatus('Kopierad till urklipp.'))
        .catch(() => setStatus('Kunde inte kopiera, markera och kopiera manuellt.', true));
    }
  }
});

init().catch((error) => {
  setStatus(error.message || 'Kunde inte ladda adminytan.', true);
});
