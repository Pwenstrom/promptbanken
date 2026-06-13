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
  apiKeys: []
};

const statusElement = document.querySelector('[data-admin-status]');
const dashboardElement = document.querySelector('[data-admin-dashboard]');
const noProfileElement = document.querySelector('[data-no-profile]');
const logoutButton = document.querySelector('[data-logout]');
const promptForm = document.querySelector('[data-prompt-form]');
const apiKeyForm = document.querySelector('[data-api-key-form]');
const refreshButtons = document.querySelectorAll('[data-refresh]');
const visibilitySelect = promptForm?.querySelector('select[name="visibility"]');

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
          <td>${escapeHtml(item.updated_at ? new Date(item.updated_at).toLocaleDateString('sv-SE') : '')}</td>
          <td>
            ${isAdminRole(state.profile.role) && item.status !== 'published'
              ? `<button type="button" data-publish-prompt="${item.id}">Publicera</button>`
              : ''}
          </td>
        </tr>
      `).join('')
    : emptyRow(5, 'Inga egna prompts ännu.');

  libraryBody.innerHTML = publishedPrompts.length
    ? publishedPrompts.map((item) => `
        <tr>
          <td>${escapeHtml(item.title)}</td>
          <td>${escapeHtml(item.visibility)}</td>
          <td>${escapeHtml(item.category || '-')}</td>
          <td>${escapeHtml(item.audience || '-')}</td>
          <td>${escapeHtml(item.published_at ? new Date(item.published_at).toLocaleDateString('sv-SE') : '')}</td>
        </tr>
      `).join('')
    : emptyRow(5, 'Inga publicerade prompts i biblioteket ännu.');
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
    .select('id, name, type, plan')
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

  dashboardElement.hidden = false;
  noProfileElement.hidden = true;
  setStatus('');
  return true;
}

async function loadPrompts() {
  const { data, error } = await supabase
    .from('content_items')
    .select('id, title, slug, summary, status, visibility, category, audience, owner_user_id, created_by, published_at, updated_at')
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
  await Promise.all([loadPrompts(), loadMembers(), loadApiKeys()]);
  setStatus('');
}

async function createPrompt(event) {
  event.preventDefault();
  if (!canEdit(state.profile.role)) {
    setStatus('Din roll får inte skapa prompts.', true);
    return;
  }

  const formData = new FormData(promptForm);
  const title = formData.get('title')?.toString().trim();
  const content = formData.get('content')?.toString().trim();
  const slug = slugify(formData.get('slug')?.toString().trim() || title);
  let visibility = formData.get('visibility')?.toString() || 'private';

  if (!allowedVisibilityOptions().some(([value]) => value === visibility)) {
    visibility = allowedVisibilityOptions()[0][0];
  }

  if (!title || !content || !slug) {
    setStatus('Titel, slug och prompttext krävs.', true);
    return;
  }

  if (isPersonalFreeWorkspace()) {
    const activeOwnPrompts = state.prompts.filter((item) => (
      item.status !== 'archived'
      && (item.owner_user_id === state.user.id || item.created_by === state.user.id)
    )).length;
    if (activeOwnPrompts >= 3) {
      setStatus('Free-läge är begränsat till 3 privata prompts. Skapa ett org-konto för fler prompts och delning.', true);
      return;
    }
  }

  const { error } = await supabase.from('content_items').insert({
    workspace_id: state.workspace.id,
    owner_user_id: state.user.id,
    type: 'prompt',
    title,
    slug,
    summary: formData.get('summary')?.toString().trim() || null,
    content,
    status: 'draft',
    visibility,
    category: formData.get('category')?.toString().trim() || null,
    audience: formData.get('audience')?.toString().trim() || null,
    created_by: state.user.id
  });

  if (error) {
    setStatus(error.message || 'Kunde inte skapa prompt.', true);
    return;
  }

  promptForm.reset();
  setStatus('Prompten sparades som utkast.');
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
  setText('[data-new-api-key]', rawKey);
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
  if (error) {
    setStatus(error.message || 'Kunde inte logga ut.', true);
    return;
  }

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
  promptForm.addEventListener('submit', createPrompt);
}

if (apiKeyForm) {
  apiKeyForm.addEventListener('submit', createApiKey);
}

refreshButtons.forEach((button) => {
  button.addEventListener('click', () => {
    refreshWorkspaceData().catch((error) => setStatus(error.message || 'Kunde inte uppdatera.', true));
  });
});

document.addEventListener('click', (event) => {
  const publishButton = event.target.closest('[data-publish-prompt]');
  const revokeButton = event.target.closest('[data-revoke-api-key]');

  if (publishButton) {
    publishPrompt(publishButton.dataset.publishPrompt);
  }

  if (revokeButton) {
    revokeApiKey(revokeButton.dataset.revokeApiKey);
  }
});

init().catch((error) => {
  setStatus(error.message || 'Kunde inte ladda adminytan.', true);
});
