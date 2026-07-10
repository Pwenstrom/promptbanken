import { requireSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const roleLabels = {
  viewer: 'Läsa publicerade prompts i workspacen.',
  editor: 'Skapa och redigera egna prompts.',
  workspace_admin: 'Publicera och administrera organisationens prompts.',
  workspace_owner: 'Äga workspace-inställningar och publiceringsflöden.',
  platform_owner: 'Skapa publika Promptbanken-prompts och administrera plattformen.'
};

const roleNameLabels = {
  viewer: 'Läsare',
  editor: 'Redigerare',
  workspace_admin: 'Administratör',
  workspace_owner: 'Ägare',
  platform_owner: 'Plattformsägare'
};

const workspaceTypeLabels = {
  personal: 'Personlig',
  organization: 'Team/organisation'
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
  proOrders: [],
  editingPromptId: null,
  myPromptsSearch: '',
  expandedPromptId: null,
  expandedOrderId: null,
  workspacesList: [],
  expandedWorkspaceId: null,
  expandedInviteWorkspaceId: null,
  workspaceInviteStatus: {},
  formIsDirty: false,
  planUsage: null
};

const riskLabels = {
  low: 'Låg risk',
  medium: 'Medelrisk',
  high: 'Hög risk'
};

// Ingen bilduppladdning för avatarer (GDPR) -- initialer + en
// deterministisk färg ur denna palett, härledd ur user.id.
const avatarPalette = [
  { background: '#dce9ff', color: '#0b63ce' },
  { background: '#dcf5e4', color: '#067647' },
  { background: '#fef0d5', color: '#92620c' },
  { background: '#f3e8ff', color: '#7c3aed' },
  { background: '#ffe4e6', color: '#be123c' },
  { background: '#e0f2fe', color: '#0369a1' }
];

function getUserInitials(user) {
  const name = user.user_metadata?.full_name || user.user_metadata?.name;
  if (name) {
    const parts = name.trim().split(/\s+/);
    const first = parts[0]?.[0] || '';
    const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
    return (first + last).toUpperCase();
  }

  return (user.email?.[0] || '?').toUpperCase();
}

function getUserAvatarStyle(user) {
  let hash = 0;
  for (const char of user.id) {
    hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  }
  return avatarPalette[hash % avatarPalette.length];
}

function renderUserAvatar(user) {
  const el = document.querySelector('.admin-user-avatar');
  if (!el) return;
  el.textContent = getUserInitials(user);
  const style = getUserAvatarStyle(user);
  el.style.background = style.background;
  el.style.color = style.color;
}

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
const upgradeForm = document.querySelector('[data-upgrade-form]');
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
  return state.planUsage?.max_prompts ?? state.workspace?.max_prompts ?? 3;
}

function mcpKeyLimit() {
  if (state.planUsage) return state.planUsage.max_mcp_keys;
  return isPlanPro() ? 3 : 1;
}

async function loadPlanUsage() {
  if (!state.workspace?.id) {
    state.planUsage = null;
    return;
  }

  const { data, error } = await supabase
    .rpc('get_plan_usage', { p_workspace_id: state.workspace.id })
    .maybeSingle();

  if (error) {
    console.error('Kunde inte hämta plananvändning', error);
    state.planUsage = null;
    return;
  }

  state.planUsage = data;
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
    return [
      ['private', 'Privat (bara du)'],
      ['workspace', 'Teamet']
    ];
  }

  return [['private', 'Privat']];
}

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

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

function setErrorStatus(error, fallbackMessage, statusFn = setStatus) {
  statusFn(getErrorMessage(error, fallbackMessage), true);
}


function setText(selector, value) {
  const text = value === undefined || value === null || value === '' ? '-' : value;
  document.querySelectorAll(selector).forEach((element) => {
    element.textContent = text;
  });
}

function setTextWithTitle(selector, value) {
  setText(selector, value);
  const text = value === undefined || value === null || value === '' ? '-' : value;
  document.querySelectorAll(selector).forEach((element) => {
    element.title = text;
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
  renderPlanLimitsSummary();
}

function renderPlanLimitsSummary() {
  const el = document.querySelector('[data-plan-limits-summary]');
  if (!el || !state.workspace) return;

  const planName = planNameLabels[state.workspace.plan] || state.workspace.plan;
  const promptLimit = maxPrompts();
  const keyLimit = mcpKeyLimit();

  if (state.workspace.type === 'organization') {
    const memberLimit = state.planUsage?.max_members;
    el.textContent = `Din plan: ${planName} — ${memberLimit ? `upp till ${memberLimit} medlemmar, ` : ''}${keyLimit} MCP-nycklar, ${promptLimit} delade mallar totalt.`;
  } else {
    el.textContent = `Din plan: ${planName} — ${promptLimit} mallar, ${keyLimit} MCP-nyckl${keyLimit === 1 ? 'a' : 'ar'}${mcpEnabled() ? '' : ' (kräver Pro)'}.`;
  }
}

function updateOrgOnlyVisibility() {
  // Visa [data-org-only] (t.ex. "Arbetsytor"-fliken) även när man tittar på
  // en personlig yta men är medlem i fler än en arbetsyta -- annars finns
  // ingen väg att växla till t.ex. en delad arbetsyta man gått med i efter
  // en omladdning som lagt en tillbaka på den personliga ytan.
  document.querySelectorAll('[data-org-only]').forEach((element) => {
    element.hidden = state.workspace.type !== 'organization'
      && !isPlatformOwner()
      && state.workspacesList.length <= 1;
  });
}

function renderCapabilityState() {
  document.querySelectorAll('[data-can-edit]').forEach((element) => {
    element.hidden = !canEdit(state.profile.role);
  });
  document.querySelectorAll('[data-admin-only]').forEach((element) => {
    element.hidden = !isAdminRole(state.profile.role);
  });

  updateOrgOnlyVisibility();

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

  const mcpTeamHint = document.querySelector('[data-mcp-team-hint]');
  if (mcpTeamHint) mcpTeamHint.hidden = state.workspace.type !== 'organization';
}

function renderOnboardingChecklist() {
  const section = document.getElementById('kom-igang');
  if (!section || state.workspace?.type !== 'organization') return;

  const hasMembers = state.members.length > 1;
  const hasMcpKey = state.mcpKeys.some((key) => !key.revoked_at);
  const hasSharedPrompt = state.prompts.some((item) => item.visibility === 'workspace');

  const steps = {
    members: hasMembers,
    mcp: hasMcpKey,
    'shared-prompt': hasSharedPrompt
  };

  Object.entries(steps).forEach(([step, done]) => {
    const item = section.querySelector(`[data-onboarding-step="${step}"]`);
    if (!item) return;
    item.classList.toggle('is-done', done);
    const check = item.querySelector('.onboarding-check');
    if (check) check.textContent = done ? '✓' : '○';
  });

  section.hidden = hasMembers && hasMcpKey && hasSharedPrompt;
}

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

function renderUpgradeSection(plan) {
  const maxedNote = document.querySelector('[data-upgrade-maxed]');
  const currentPlanNote = document.querySelector('[data-upgrade-current-plan-note]');
  const form = document.querySelector('[data-upgrade-form]');
  const isMaxed = plan === 'enterprise';

  if (maxedNote) maxedNote.hidden = !isMaxed;
  if (form) form.hidden = isMaxed;
  if (currentPlanNote) {
    currentPlanNote.textContent = `Nuvarande nivå: ${planNameLabels[plan] || plan}`;
  }
}

function renderPlanInfo() {
  const plan = state.workspace?.plan ?? 'free';
  const isOrg = state.workspace?.type === 'organization';
  const badge = document.querySelector('[data-plan-badge]');
  const desc = document.querySelector('[data-plan-badge-desc]');
  const featureList = document.querySelector('[data-plan-feature-list]');
  const maxP = maxPrompts();

  const panel = document.querySelector('.plan-panel');
  if (panel) panel.dataset.planWorld = isOrg ? 'organization' : 'personal';

  if (badge) {
    badge.textContent = planNameLabels[plan] ?? plan;
    badge.dataset.plan = plan;
  }
  if (desc) {
    desc.textContent = isOrg ? 'Organisationskonto' : 'Personligt konto';
  }

  setText('[data-workspace-plan]', planNameLabels[plan] ?? plan);

  renderPlanExpiry();
  renderUpgradeSection(plan);
  renderPlanLimitsSummary();
  renderPlanMeters();
  renderPlanNextSteps();

  const features = isOrg
    ? [
        { label: `${maxP} delade mallar (hela licensen)`, ok: true },
        { label: 'Dela prompts med hela teamet', ok: true },
        { label: `${mcpKeyLimit()} MCP-nycklar för agenter/integrationer`, ok: mcpEnabled() },
        { label: 'API-nycklar för externa integrationer', ok: apiEnabled() },
        { label: 'Premium-mallar (Pro-biblioteket)', ok: true }
      ]
    : [
        { label: `${maxP} egna mallar`, ok: true },
        { label: 'MCP-nyckel (egna + publika prompts)', ok: mcpEnabled() },
        { label: 'API-nycklar för externa integrationer', ok: apiEnabled() },
        { label: 'Premium-mallar (Pro-biblioteket)', ok: isPlanPro() }
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

const planNameLabels = { free: 'Free', pro: 'Pro', start: 'Delad arbetsyta', plus: 'Förvaltning', enterprise: 'Kommun' };

function renderPromptCounter(ownActivePrompts) {
  const limit = maxPrompts();
  const isOrg = state.workspace?.type === 'organization';
  const isOrgLicense = isOrg && state.planUsage?.has_license;
  // Både licensorganisationer och delade addon-ytor har en poolad gräns
  // (över syskonytor respektive över hela ytans medlemmar) -- bara sant
  // personliga workspaces räknar enbart den inloggades egna prompts.
  const usedCount = isOrg ? (state.planUsage?.used_prompts ?? ownActivePrompts) : ownActivePrompts;
  const atLimit = usedCount >= limit;
  const plan = state.workspace?.plan ?? 'free';

  setText('[data-mp-plan-name]', planNameLabels[plan] || plan);
  setText('[data-mp-used-count]', usedCount);
  setText('[data-mp-max-count]', limit);

  const usedLabel = document.querySelector('[data-mp-used-label]');
  if (usedLabel) {
    usedLabel.textContent = isOrgLicense
      ? 'hela licensen (alla arbetsytor)'
      : isOrg
        ? 'hela den delade arbetsytan'
        : 'dina egna';
  }

  const bar = document.querySelector('[data-mp-usage-bar]');
  if (bar) {
    bar.style.width = `${Math.min(100, Math.round((usedCount / limit) * 100))}%`;
    bar.parentElement?.classList.toggle('is-at-limit', atLimit);
  }

  const statusMetric = document.querySelector('[data-mp-status-metric]');
  const statusNote = document.querySelector('[data-mp-status-note]');
  if (statusMetric) {
    statusMetric.textContent = atLimit ? 'Fullt' : 'OK';
    statusMetric.classList.toggle('mp-bad', atLimit);
    statusMetric.classList.toggle('mp-ok', !atLimit);
  }
  if (statusNote) {
    statusNote.textContent = atLimit
      ? 'Ta bort en mall för att skapa ny'
      : 'Du kan skapa fler mallar';
  }

  const limitNotice = document.querySelector('[data-mp-limit-notice]');
  const limitNoticeText = document.querySelector('[data-mp-limit-notice-text]');
  if (limitNotice) {
    limitNotice.hidden = !atLimit;
    if (limitNoticeText) {
      limitNoticeText.textContent = `Du har skapat max antal prompts (${limit} st). Ta bort en mall eller uppgradera för att skapa fler.`;
    }
  }

  const upgradeTip = document.querySelector('[data-mp-upgrade-tip]');
  if (upgradeTip) {
    upgradeTip.hidden = plan !== 'free';
  }
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

  const statusLabels = { draft: 'Utkast', review: 'Granskning', published: 'Publicerad', archived: 'Arkiverad' };

  if (!allOwnPrompts.length) {
    mineBody.innerHTML = '<div class="mp-empty">Du har inga prompts än. Fyll i formuläret ovan för att skapa din första!</div>';
  } else if (!ownPrompts.length) {
    mineBody.innerHTML = `<div class="mp-empty">Inga prompts matchar "${escapeHtml(state.myPromptsSearch)}".</div>`;
  } else {
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
  renderPlanMeters();
}

function renderPlanMeters() {
  const container = document.querySelector('[data-plan-meters]');
  if (!container || !state.workspace) return;

  const isOrg = state.workspace.type === 'organization';
  const promptLimit = maxPrompts();
  // Poolad räkning gäller alla organisationstyper (licens- och addon-ytor),
  // inte bara licensorganisationer -- se renderPromptCounter ovan.
  const promptsUsed = isOrg
    ? (state.planUsage?.used_prompts ?? 0)
    : state.prompts.filter((item) => (
        (item.owner_user_id === state.user?.id || item.created_by === state.user?.id) && item.status !== 'archived'
      )).length;

  const keyLimit = mcpKeyLimit();
  const keysUsed = state.mcpKeys.filter((key) => !key.revoked_at).length;

  const meters = [
    { label: isOrg ? 'Delade mallar' : 'Egna mallar', used: promptsUsed, max: promptLimit },
    { label: 'MCP-nycklar', used: keysUsed, max: keyLimit }
  ];

  if (isOrg && state.planUsage?.max_members) {
    meters.push({ label: 'Medlemmar', used: state.members.length, max: state.planUsage.max_members });
  }

  container.innerHTML = meters.map(({ label, used, max }) => {
    const pct = max ? Math.min(100, Math.round((used / max) * 100)) : 0;
    const atLimit = Boolean(max) && used >= max;
    return `
      <div class="plan-meter${atLimit ? ' is-at-limit' : ''}">
        <div class="plan-meter-row">
          <span class="plan-meter-label">${escapeHtml(label)}</span>
          <span class="plan-meter-value">${used} / ${max ?? '—'}</span>
        </div>
        <div class="plan-meter-track"><div class="plan-meter-fill" style="width:${pct}%"></div></div>
      </div>
    `;
  }).join('');
}

const nextStepsByPlan = {
  free: ['pro'],
  pro: ['start', 'plus'],
  start: ['plus'],
  plus: ['enterprise'],
  enterprise: []
};

const planNextStepBlurbs = {
  pro: 'Hela premiumbiblioteket, 100 egna mallar, 3 MCP-nycklar.',
  start: 'Dela mallar i en gemensam yta. Upp till 5 Pro-användare.',
  plus: 'Flera arbetsytor under en gemensam licens, upp till 50 medlemmar.',
  enterprise: 'Central styrning för hela kommunen, 250+ medlemmar.'
};

function renderPlanNextSteps() {
  const container = document.querySelector('[data-plan-next-steps]');
  if (!container || !state.workspace) return;

  const plan = state.workspace.plan ?? 'free';
  const steps = nextStepsByPlan[plan] || [];

  if (!steps.length) {
    container.innerHTML = '<p class="plan-locked-note">Ni har redan högsta nivån (Kommun).</p>';
    return;
  }

  container.innerHTML = steps.map((stepPlan, index) => {
    const pricing = planPricing[stepPlan];
    const selfService = planIsSelfService(stepPlan);
    return `
      <article class="plan-next-tile${index === 0 ? ' plan-next-tile--primary' : ''}">
        <p class="plan-next-tile-name">${escapeHtml(upgradePlanLabels[stepPlan] || stepPlan)}</p>
        <p class="plan-next-tile-price">${escapeHtml(pricing?.amount || '—')}</p>
        <p class="plan-next-tile-blurb">${escapeHtml(planNextStepBlurbs[stepPlan] || '')}</p>
        <button type="button" class="${index === 0 ? 'primary-btn' : 'secondary-btn'}" data-select-plan="${stepPlan}">
          ${selfService ? 'Lägg till' : 'Kontakta oss'}
        </button>
      </article>
    `;
  }).join('');
}

function selectUpgradePlan(plan) {
  if (!upgradeForm) return;
  const select = upgradeForm.querySelector('select[name="plan"]');
  if (select) select.value = plan;
  syncUpgradeWorkspacesField();
  document.getElementById('uppgradera')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  upgradeForm.querySelector('input[name="company_name"]')?.focus();
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

function renderProOrders() {
  const body = document.querySelector('[data-pro-orders]');
  if (!body) return;
  body.innerHTML = state.proOrders.length
    ? state.proOrders.map((order) => `
        <tr>
          <td>${escapeHtml(order.billing_company_name || '-')}</td>
          <td>${escapeHtml(upgradePlanLabels[order.requested_plan] || order.requested_plan)}</td>
          <td>${escapeHtml(order.requested_workspaces)}</td>
          <td>${escapeHtml(order.billing_email || '-')}</td>
          <td><span class="order-status-chip" data-status="${escapeHtml(order.status)}">${escapeHtml(order.status)}</span></td>
          <td>${escapeHtml(order.due_date ? new Date(order.due_date).toLocaleDateString('sv-SE') : '-')}</td>
          <td>
            <button type="button" data-preview-order="${order.id}">${state.expandedOrderId === order.id ? 'Dölj' : 'Visa'}</button>
            ${(order.status === 'pending' && !order.license_id && ['plus', 'enterprise'].includes(order.requested_plan))
              ? `<button type="button" class="primary-btn" data-activate-order="${order.id}">Aktivera</button>`
              : ''}
            ${order.status === 'pending' ? `<button type="button" data-mark-invoiced="${order.id}">Markera fakturerad</button>` : ''}
            ${order.status === 'invoiced' ? `<button type="button" data-mark-paid="${order.id}">Markera betald</button>` : ''}
            ${order.status !== 'cancelled' ? `<button type="button" data-downgrade-order="${order.id}" data-delete-confirm="0">Nedgradera till Free</button>` : ''}
          </td>
        </tr>
        ${state.expandedOrderId === order.id ? `
        <tr class="prompt-preview-row">
          <td colspan="7">
            <div class="order-detail-grid">
              <div><span>Beställnings-ID</span><code>${escapeHtml(order.id)}</code></div>
              <div><span>Workspace-ID</span><code>${escapeHtml(order.workspace_id || '-')}</code></div>
              <div><span>Licens-ID</span><code>${escapeHtml(order.license_id || '-')}</code></div>
              <div><span>Org.nummer</span>${escapeHtml(order.billing_org_number || '-')}</div>
              <div><span>Fakturaadress</span>${escapeHtml(order.billing_address || '-')}</div>
              <div><span>Referens/kostnadsställe</span>${escapeHtml(order.billing_reference || '-')}</div>
              <div><span>Beställd</span>${escapeHtml(order.created_at ? new Date(order.created_at).toLocaleString('sv-SE') : '-')}</div>
              <div><span>Notering</span>${escapeHtml(order.note || '-')}</div>
            </div>
          </td>
        </tr>` : ''}
      `).join('')
    : emptyRow(7, 'Ingen beställning ännu.');
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
    setErrorStatus(error, 'Kunde inte skapa MCP-nyckel.');
    return;
  }

  mcpKeyForm.reset();
  showSecret('mcp-key', rawKey);
  setStatus('MCP-nyckeln skapades. Kopiera den nu, den visas bara en gång.');
  await loadMcpKeys();
}

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
        'X-MCP-Key': rawKey
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'tools/call',
        params: { name: 'list_my_prompts', arguments: {} }
      })
    });

    if (!response.ok) {
      statusEl.textContent = `Servern svarade med ett oväntat fel (status ${response.status}).`;
      statusEl.classList.add('is-error');
      return;
    }

    const body = await response.json();

    if (body?.error) {
      statusEl.textContent = `Servern svarade med ett oväntat fel (${body.error.message || body.error.code}).`;
      statusEl.classList.add('is-error');
      return;
    }

    const resultText = body?.result?.content?.[0]?.text;
    let parsed = null;
    try {
      parsed = resultText ? JSON.parse(resultText) : null;
    } catch {
      parsed = null;
    }
    const workspaceStatus = parsed?.workspace_status;

    if (workspaceStatus === 'invalid_key' || workspaceStatus === 'no_key') {
      statusEl.textContent = 'Servern avvisade nyckeln. Kontrollera att du kopierade hela nyckeln.';
      statusEl.classList.add('is-error');
    } else if (body?.result?.isError || !parsed || !Array.isArray(parsed.prompts)) {
      statusEl.textContent = 'Kunde inte tolka svaret från servern. Försök igen om en stund.';
      statusEl.classList.add('is-error');
    } else {
      statusEl.textContent = 'Anslutningen fungerar. Nyckeln accepterades av servern.';
    }
  } catch {
    statusEl.textContent = 'Kunde inte nå servern. Kontrollera din internetanslutning och försök igen.';
    statusEl.classList.add('is-error');
  }
}

async function revokeMcpKey(keyId) {
  const { error } = await supabase
    .from('api_keys')
    .update({ revoked_at: new Date().toISOString() })
    .eq('id', keyId)
    .eq('workspace_id', state.workspace.id);

  if (error) {
    setErrorStatus(error, 'Kunde inte återkalla MCP-nyckel.');
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
  renderUserAvatar(user);
  setTextWithTitle('[data-workspace-name]', workspace.name);
  setText('[data-workspace-type]', workspaceTypeLabels[workspace.type] || workspace.type);
  setText('[data-workspace-plan]', planNameLabels[workspace.plan] || workspace.plan);
  setText('[data-profile-role]', roleNameLabels[profile.role] || profile.role);
  renderRoleMode(profile.role);
  renderCapabilityState();
  renderPromptFormRules();
  renderPlanInfo();

  dashboardElement.hidden = false;
  noProfileElement.hidden = true;
  setStatus('');
  return true;
}

async function switchToWorkspace(workspaceId) {
  const { data: profileRow, error: profileError } = await supabase
    .from('profiles')
    .select('id, role, workspace_id')
    .eq('user_id', state.user.id)
    .eq('workspace_id', workspaceId)
    .maybeSingle();

  if (profileError) throw profileError;

  // Plattformsägare kan sakna ett eget medlemskap i en arbetsyta men
  // ska ändå kunna växla in för att titta/administrera (bypassar RLS
  // via current_user_is_platform_owner() i övriga policyer).
  const profile = profileRow || (isPlatformOwner() ? { role: 'platform_owner', workspace_id: workspaceId } : null);
  if (!profile) {
    throw new Error('Du är inte medlem i den här arbetsytan.');
  }

  const { data: workspace, error: workspaceError } = await supabase
    .from('workspaces')
    .select('id, name, type, plan, api_enabled, mcp_enabled, max_prompts, plan_source, plan_expires_at')
    .eq('id', workspaceId)
    .single();

  if (workspaceError) throw workspaceError;

  state.profile = profile;
  state.workspace = workspace;

  setTextWithTitle('[data-workspace-name]', workspace.name);
  setText('[data-workspace-type]', workspaceTypeLabels[workspace.type] || workspace.type);
  setText('[data-workspace-plan]', planNameLabels[workspace.plan] || workspace.plan);
  setText('[data-profile-role]', roleNameLabels[profile.role] || profile.role);
  renderRoleMode(profile.role);
  renderCapabilityState();
  renderPromptFormRules();
  renderPlanInfo();

  await refreshWorkspaceData();
}

async function loadWorkspaces() {
  const list = document.querySelector('[data-workspaces-list]');
  if (!list) return;

  const { data: myProfiles } = await supabase
    .from('profiles')
    .select('workspace_id, role')
    .eq('user_id', state.user.id);

  const roleByWorkspace = new Map((myProfiles || []).map((p) => [p.workspace_id, p.role]));
  const myWorkspaceIds = (myProfiles || []).map((p) => p.workspace_id);

  // Bara en yta och ingen organisationskontext: ingen switcher att visa.
  if (state.workspace?.type !== 'organization' && !isPlatformOwner() && myWorkspaceIds.length <= 1) {
    state.workspacesList = [];
    renderWorkspaces();
    return;
  }

  let query = supabase.from('workspaces').select('id, name, type, plan, license_id');

  if (isPlatformOwner()) {
    // Plattformsägaren ser alla arbetsytor i hela systemet.
  } else if (state.workspace?.license_id) {
    query = query.eq('license_id', state.workspace.license_id);
  } else {
    // Ingen delad licens: visa alla arbetsytor användaren själv är medlem
    // i (t.ex. personlig Pro-yta + en delad arbetsyta), inte bara den just
    // nu visade ytan -- annars finns ingen väg tillbaka till t.ex. sin
    // personliga yta och dess egna MCP-nycklar efter att ha skapat eller
    // gått med i en delad arbetsyta.
    query = query.in('id', myWorkspaceIds.length ? myWorkspaceIds : [state.workspace.id]);
  }

  const { data, error } = await query.order('name', { ascending: true });
  if (error) {
    setErrorStatus(error, 'Kunde inte ladda arbetsytor.');
    return;
  }

  state.workspacesList = (data || []).map((w) => ({ ...w, myRole: roleByWorkspace.get(w.id) || null }));

  const scopeNote = document.querySelector('[data-workspaces-scope-note]');
  if (scopeNote) {
    scopeNote.textContent = isPlatformOwner()
      ? 'Alla arbetsytor i systemet (plattformsadmin-vy).'
      : state.workspace?.license_id
        ? 'Arbetsytorna under er licens.'
        : 'Dina arbetsytor.';
  }

  renderWorkspaces();
}

function renderWorkspaceSwitch() {
  const select = document.querySelector('[data-workspace-switch]');
  if (!select) return;

  if (state.workspacesList.length <= 1) {
    select.hidden = true;
    select.innerHTML = '';
    return;
  }

  select.innerHTML = state.workspacesList.map((w) => (
    `<option value="${w.id}"${w.id === state.workspace.id ? ' selected' : ''}>${escapeHtml(w.name)} (${escapeHtml(planNameLabels[w.plan] || w.plan)})</option>`
  )).join('');
  select.hidden = false;
}

function renderWorkspaces() {
  updateOrgOnlyVisibility();
  renderWorkspaceSwitch();

  const list = document.querySelector('[data-workspaces-list]');
  if (!list) return;

  if (!state.workspacesList.length) {
    list.innerHTML = '<div class="mp-empty">Inga arbetsytor hittades.</div>';
    return;
  }

  list.innerHTML = state.workspacesList.map((w) => {
    const canInvite = w.type === 'organization' && isAdminRole(w.myRole);
    const canDelete = w.type === 'organization' && w.myRole === 'workspace_owner';
    const inviteStatus = state.workspaceInviteStatus[w.id];
    return `
      <article class="mp-template">
        <div>
          <h3>${escapeHtml(w.name)}</h3>
          <p>${escapeHtml(workspaceTypeLabels[w.type] || w.type)} · ${escapeHtml(planNameLabels[w.plan] || w.plan)}${w.myRole ? ` · Din roll: ${escapeHtml(roleNameLabels[w.myRole] || w.myRole)}` : ''}</p>
        </div>
        <div class="mp-menu">
          ${w.id !== state.workspace.id
            ? `<button type="button" data-switch-workspace="${w.id}">Byt till</button>`
            : '<span class="order-status-chip" data-status="paid">Aktiv yta</span>'}
          <button type="button" data-quick-create-toggle="${w.id}">${state.expandedWorkspaceId === w.id ? 'Stäng' : '+ Snabb prompt'}</button>
          ${canInvite ? `<button type="button" data-invite-toggle="${w.id}">${state.expandedInviteWorkspaceId === w.id ? 'Stäng' : '+ Bjud in kollega'}</button>` : ''}
          ${canDelete ? `<button type="button" class="danger-btn" data-delete-workspace="${w.id}" data-delete-workspace-name="${escapeHtml(w.name)}">Radera arbetsyta</button>` : ''}
        </div>
      </article>
      ${state.expandedWorkspaceId === w.id ? `
      <div class="mp-quick-create">
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
      </div>` : ''}
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
    `;
  }).join('');
}

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

  if (error) {
    setErrorStatus(error, 'Kunde inte skapa prompten.');
    return;
  }

  setStatus('Prompten sparades som utkast.');
  state.expandedWorkspaceId = null;
  renderWorkspaces();

  if (workspaceId === state.workspace.id) {
    await loadPrompts();
  }
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
    setErrorStatus(error, 'Kunde inte bjuda in medlem.');
    return;
  }

  inviteMemberForm.reset();
  setStatus(`${email} har lagts till i workspacet.`);
  await loadMembers();
}

// Samma invite_org_member-RPC som inviteOrgMember, men riktad mot en
// specifik arbetsyta i Arbetsytor-listan istället för den just nu
// aktiva ytan -- så man slipper byta yta först för att bjuda in någon
// till en annan yta man administrerar.
async function submitWorkspaceInvite(event) {
  event.preventDefault();
  const form = event.target;
  const workspaceId = form.dataset.workspaceId;
  const formData = new FormData(form);
  const email = formData.get('email')?.toString().trim();
  const role = formData.get('role')?.toString() || 'editor';

  if (!email) {
    state.workspaceInviteStatus[workspaceId] = { message: 'E-post krävs.', isError: true };
    renderWorkspaces();
    return;
  }

  const { error } = await supabase.rpc('invite_org_member', {
    p_workspace_id: workspaceId,
    p_email: email,
    p_role: role
  });

  if (error) {
    state.workspaceInviteStatus[workspaceId] = { message: getErrorMessage(error, 'Kunde inte bjuda in medlem.'), isError: true };
    renderWorkspaces();
    return;
  }

  state.workspaceInviteStatus[workspaceId] = { message: `${email} har lagts till.`, isError: false };
  renderWorkspaces();

  if (workspaceId === state.workspace.id) {
    await loadMembers();
  }
}

// Raderar en arbetsyta permanent (organisationsytor bara, ägare/platform_owner
// bara -- se delete_workspace-RPC:n). content_items/profiles/api_keys/
// org_join_codes/shared_workspace_addons cascadas bort automatiskt via
// workspace_id-foreign keys i schemat.
async function deleteWorkspaceFromList(workspaceId, workspaceName) {
  const { count } = await supabase
    .from('content_items')
    .select('id', { count: 'exact', head: true })
    .eq('workspace_id', workspaceId)
    .eq('type', 'prompt')
    .neq('status', 'archived');

  const promptWarning = count
    ? `Arbetsytan innehåller ${count} sparad${count === 1 ? '' : 'e'} prompt${count === 1 ? '' : 'ar'} som tas bort permanent tillsammans med ytan. `
    : '';

  const confirmed = window.confirm(
    `Radera arbetsytan "${workspaceName}" permanent? ${promptWarning}` +
    'Alla medlemmar, nycklar och delade mallar i arbetsytan tas bort och går inte att återfå.'
  );
  if (!confirmed) {
    return;
  }

  const { error } = await supabase.rpc('delete_workspace', { p_workspace_id: workspaceId });
  if (error) {
    setErrorStatus(error, 'Kunde inte radera arbetsytan.');
    return;
  }

  setStatus(`"${workspaceName}" raderades.`);

  if (workspaceId === state.workspace.id) {
    // Vi raderade ytan vi just nu står i -- ladda om för att landa på en
    // yta som fortfarande finns (loadProfile väljer äldsta kvarvarande profil).
    window.location.reload();
    return;
  }

  state.workspacesList = state.workspacesList.filter((w) => w.id !== workspaceId);
  renderWorkspaces();
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
    setErrorStatus(error, 'Kunde inte skapa join-länk.');
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
    setErrorStatus(error, 'Kunde inte återkalla join-länken.');
    return;
  }

  setStatus('Join-länken återkallades.');
  await loadJoinCodes();
}

const upgradePlanLabels = {
  pro: 'Pro',
  start: 'Delad arbetsyta',
  plus: 'Förvaltning',
  enterprise: 'Kommun'
};

// Priser fyllda med riktiga belopp av produktägaren. Self-service-nivåer
// (pro/start) har ett fast pris; org-nivåer (plus/enterprise) prissätts
// via offert och aktiveras först efter godkännande (se B2).
// TODO: bekräfta beloppen innan publik release.
const planPricing = {
  pro: { amount: '89 kr/mån', note: 'faktureras i efterskott', selfService: true },
  start: { amount: 'Pro + 199 kr/mån', note: 'delad yta, upp till 5 Pro-användare · faktureras i efterskott', selfService: true },
  plus: { amount: 'Pris enligt offert', note: 'vi kontaktar er innan avtal och fakturering', selfService: false },
  enterprise: { amount: 'Pris enligt offert', note: 'vi kontaktar er innan avtal och fakturering', selfService: false }
};

function planIsSelfService(plan) {
  return planPricing[plan]?.selfService === true;
}

function renderUpgradePrice() {
  if (!upgradeForm) return;
  const plan = upgradeForm.querySelector('select[name="plan"]')?.value;
  const pricing = planPricing[plan];
  const amountEl = document.querySelector('[data-upgrade-price-amount]');
  const noteEl = document.querySelector('[data-upgrade-price-note]');
  const submitBtn = document.querySelector('[data-upgrade-submit]');

  if (amountEl) amountEl.textContent = pricing?.amount || '—';
  if (noteEl) noteEl.textContent = pricing?.note || '';
  if (submitBtn) {
    submitBtn.textContent = planIsSelfService(plan) ? 'Granska beställning' : 'Skicka förfrågan';
  }

  const selfService = planIsSelfService(plan);
  const badgeEl = document.querySelector('[data-order-mode-badge]');
  if (badgeEl) {
    badgeEl.textContent = selfService ? 'Aktiveras direkt' : 'Förfrågan — ej bindande';
    badgeEl.classList.toggle('is-request', !selfService);
  }

  const blurbEl = document.querySelector('[data-order-blurb]');
  if (blurbEl) blurbEl.textContent = planNextStepBlurbs[plan] || '';
}

function setUpgradeStatus(message, isError = false) {
  const el = document.querySelector('[data-upgrade-status]');
  if (!el) return;
  el.textContent = message;
  el.hidden = !message;
  el.classList.toggle('is-error', isError);
}

function syncUpgradeWorkspacesField() {
  if (!upgradeForm) return;
  const plan = upgradeForm.querySelector('select[name="plan"]')?.value;
  const field = document.querySelector('[data-upgrade-workspaces-field]');
  // Pro har ett fast antal arbetsytor (1) -- Delad arbetsyta, Förvaltning
  // och Kommun kan alla välja hur många arbetsytor de vill börja med.
  // TODO: sätt ett per-plan max på input[name="workspaces"] när en verklig
  // gräns är beslutad -- idag går det att skriva in ett godtyckligt antal.
  const fixedWorkspaces = plan === 'pro';
  if (field) {
    field.hidden = fixedWorkspaces;
    if (fixedWorkspaces) {
      const input = field.querySelector('input[name="workspaces"]');
      if (input) input.value = 1;
    }
  }

  const teamNameField = document.querySelector('[data-upgrade-team-name-field]');
  if (teamNameField) {
    teamNameField.hidden = plan === 'pro';
  }

  renderUpgradePrice();
  hideUpgradeConfirm();
}

// Beställningen som väntar på användarens bekräftelse (steg 1 -> steg 2).
let pendingUpgradeOrder = null;

function hideUpgradeConfirm() {
  pendingUpgradeOrder = null;
  const panel = document.querySelector('[data-upgrade-confirm-panel]');
  if (panel) panel.hidden = true;
}

// Steg 1: validera och visa en sammanfattning att bekräfta -- anropar
// INTE databasen ännu.
function reviewUpgradeOrder(event) {
  event.preventDefault();

  const formData = new FormData(upgradeForm);
  const plan = formData.get('plan')?.toString();
  const workspaces = Number(formData.get('workspaces')) || 1;
  const workspaceName = formData.get('workspace_name')?.toString().trim() || null;
  const companyName = formData.get('company_name')?.toString().trim();
  const orgNumber = formData.get('org_number')?.toString().trim() || null;
  const address = formData.get('address')?.toString().trim() || null;
  const reference = formData.get('reference')?.toString().trim() || null;
  const billingEmail = formData.get('billing_email')?.toString().trim();

  if (!companyName || !billingEmail) {
    setUpgradeStatus('Företag/kommun och fakturamejl krävs.', true);
    return;
  }

  pendingUpgradeOrder = {
    plan, workspaces, workspaceName, companyName, orgNumber, address, reference, billingEmail
  };

  const pricing = planPricing[plan];
  const selfService = planIsSelfService(plan);

  const summary = document.querySelector('[data-upgrade-confirm-summary]');
  if (summary) {
    const rows = [
      ['Nivå', upgradePlanLabels[plan] || plan],
      ['Pris', pricing?.amount || '—'],
      ['Företag/kommun', companyName],
      workspaceName ? ['Arbetsyta', workspaceName] : null,
      !selfService && workspaces > 1 ? ['Antal arbetsytor', String(workspaces)] : null,
      ['Fakturamejl', billingEmail]
    ].filter(Boolean);
    summary.innerHTML = rows
      .map(([k, v]) => `<div><dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd></div>`)
      .join('');
  }

  const terms = document.querySelector('[data-upgrade-confirm-terms]');
  if (terms) {
    terms.textContent = selfService
      ? `${upgradePlanLabels[plan] || plan} aktiveras direkt. En faktura på ${pricing?.amount || 'angivet belopp'} skickas till ${billingEmail}.`
      : `Detta är en förfrågan, inte ett bindande köp. Vi kontaktar er på ${billingEmail} med offert innan avtal tecknas och kontot aktiveras.`;
  }

  const confirmBtn = document.querySelector('[data-upgrade-confirm]');
  if (confirmBtn) {
    confirmBtn.textContent = selfService ? 'Bekräfta och beställ' : 'Skicka förfrågan';
  }

  const panel = document.querySelector('[data-upgrade-confirm-panel]');
  if (panel) panel.hidden = false;
  setUpgradeStatus('');
}

// Steg 2: användaren har bekräftat -- skapa ordern.
async function confirmUpgradeOrder() {
  if (!pendingUpgradeOrder) return;
  const order = pendingUpgradeOrder;

  setUpgradeStatus('Skickar beställning...');
  hideUpgradeConfirm();

  // Delad arbetsyta är ett Pro-tillägg med egen väg (skapar ingen pro_order/licens).
  if (order.plan === 'start') {
    const { data: sharedData, error: sharedError } = await supabase.rpc('create_shared_workspace', {
      p_name: order.workspaceName || order.companyName
    });
    if (sharedError) {
      setUpgradeStatus(sharedError.message || 'Kunde inte skapa den delade arbetsytan.', true);
      return;
    }
    const created = Array.isArray(sharedData) ? sharedData[0] : sharedData;
    setUpgradeStatus('Delad arbetsyta skapad. Faktura på 199 kr/mån skickas.');
    upgradeForm.reset();
    syncUpgradeWorkspacesField();
    if (created?.workspace_id) {
      await switchToWorkspace(created.workspace_id);
    } else {
      await loadProfile(state.user);
    }
    return;
  }

  const { data, error } = await supabase.rpc('create_pro_order', {
    p_requested_plan: order.plan,
    p_requested_workspaces: order.workspaces,
    p_billing_company_name: order.companyName,
    p_billing_org_number: order.orgNumber,
    p_billing_address: order.address,
    p_billing_reference: order.reference,
    p_billing_email: order.billingEmail,
    p_workspace_name: order.workspaceName
  });

  if (error) {
    setErrorStatus(error, 'Kunde inte skapa beställningen.', setUpgradeStatus);
    return;
  }

  const result = Array.isArray(data) ? data[0] : data;
  const activated = result?.activated !== false;

  if (activated) {
    setUpgradeStatus(`${upgradePlanLabels[order.plan] || order.plan} är aktiverat. Faktura skickas till ${order.billingEmail}.`);
  } else {
    setUpgradeStatus(`Tack! Din förfrågan om ${upgradePlanLabels[order.plan] || order.plan} har registrerats. Vi kontaktar dig på ${order.billingEmail} med offert innan aktivering.`);
  }

  upgradeForm.reset();
  syncUpgradeWorkspacesField();

  if (activated && result?.workspace_id && result.workspace_id !== state.workspace.id) {
    await switchToWorkspace(result.workspace_id);
  } else {
    await loadProfile(state.user);
  }
}

async function renameWorkspace(event) {
  event.preventDefault();
  if (!isAdminRole(state.profile.role)) {
    setStatus('Din roll får inte byta namn på workspacet.', true);
    return;
  }

  const form = event.target;
  const name = new FormData(form).get('name')?.toString().trim();
  if (!name) {
    setStatus('Namnet får inte vara tomt.', true);
    return;
  }

  const { error } = await supabase.rpc('rename_workspace', {
    p_workspace_id: state.workspace.id,
    p_name: name
  });

  if (error) {
    setErrorStatus(error, 'Kunde inte byta namn.');
    return;
  }

  state.workspace.name = name;
  setTextWithTitle('[data-workspace-name]', name);
  form.hidden = true;
  form.reset();
  setStatus('Namnet uppdaterades.');
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
  await loadPlanUsage();
  renderPlanInfo();
  renderCapabilityState();
  await Promise.all([loadPrompts(), loadMembers(), loadJoinCodes(), loadMcpKeys(), loadApiKeys(), loadProInvites(), loadProOrders(), loadWorkspaces()]);
  renderOnboardingChecklist();
  renderPersonalOnboarding();
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
    setErrorStatus(error, 'Kunde inte spara prompt.');
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
    setErrorStatus(error, 'Kunde inte ta bort prompt.');
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
    setErrorStatus(error, 'Kunde inte avpublicera prompt.');
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
    setErrorStatus(error, 'Kunde inte publicera prompt.');
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
    setErrorStatus(error, 'Kunde inte skapa API-nyckel.');
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

async function loadProOrders() {
  if (!isPlatformOwner()) {
    state.proOrders = [];
    renderProOrders();
    return;
  }

  const { data, error } = await supabase
    .from('pro_orders')
    .select('id, license_id, workspace_id, requested_plan, requested_workspaces, billing_company_name, billing_org_number, billing_address, billing_reference, billing_email, status, due_date, created_at, note')
    .order('created_at', { ascending: false });

  if (error) throw error;
  state.proOrders = data || [];
  renderProOrders();
}

async function markOrderInvoiced(orderId) {
  const dueDate = new Date();
  dueDate.setDate(dueDate.getDate() + 30);

  const { error } = await supabase
    .from('pro_orders')
    .update({ status: 'invoiced', due_date: dueDate.toISOString() })
    .eq('id', orderId);

  if (error) {
    setErrorStatus(error, 'Kunde inte markera som fakturerad.');
    return;
  }

  setStatus('Markerad som fakturerad (förfaller om 30 dagar).');
  await loadProOrders();
}

async function markOrderPaid(orderId) {
  const { error } = await supabase
    .from('pro_orders')
    .update({ status: 'paid' })
    .eq('id', orderId);

  if (error) {
    setErrorStatus(error, 'Kunde inte markera som betald.');
    return;
  }

  setStatus('Markerad som betald.');
  await loadProOrders();
}

async function activateProOrder(orderId) {
  const { error } = await supabase.rpc('admin_activate_pro_order', { p_order_id: orderId });

  if (error) {
    setErrorStatus(error, 'Kunde inte aktivera beställningen.');
    return;
  }

  setStatus('Beställningen aktiverades — licens och arbetsyta har skapats åt beställaren.');
  await loadProOrders();
}

async function downgradeProOrder(orderId) {
  const { error } = await supabase.rpc('admin_downgrade_pro_order', { p_order_id: orderId });

  if (error) {
    setErrorStatus(error, 'Kunde inte nedgradera beställningen.');
    return;
  }

  setStatus('Workspacet/licensen har nedgraderats till Free.');
  await loadProOrders();
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
    setErrorStatus(error, 'Kunde inte skapa inbjudan.');
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
    setErrorStatus(error, 'Kunde inte göra användaren till admin.');
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
    const message = data?.error || getErrorMessage(error, 'Kunde inte radera kontot.');
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
    setErrorStatus(error, 'Kunde inte återkalla API-nyckel.');
    return;
  }

  setStatus('API-nyckeln återkallades.');
  await loadApiKeys();
}

async function logout() {
  setStatus('Loggar ut...');
  const { error } = await supabase.auth.signOut();
  if (error && error.name !== 'AuthSessionMissingError') {
    setErrorStatus(error, 'Kunde inte logga ut.');
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

const workspaceSwitchSelect = document.querySelector('[data-workspace-switch]');
if (workspaceSwitchSelect) {
  workspaceSwitchSelect.addEventListener('change', () => {
    switchToWorkspace(workspaceSwitchSelect.value).catch((error) => {
      setErrorStatus(error, 'Kunde inte byta arbetsyta.');
    });
  });
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
  const roleSelect = inviteMemberForm.querySelector('[data-invite-role-select]');
  const roleHint = document.querySelector('[data-invite-role-hint]');
  if (roleSelect && roleHint) {
    roleSelect.addEventListener('change', () => {
      roleHint.textContent = roleLabels[roleSelect.value] || '';
    });
  }
}

const generateJoinCodeButton = document.querySelector('[data-generate-join-code]');
if (generateJoinCodeButton) {
  generateJoinCodeButton.addEventListener('click', generateJoinCode);
}

if (upgradeForm) {
  upgradeForm.addEventListener('submit', reviewUpgradeOrder);
  upgradeForm.querySelector('select[name="plan"]')?.addEventListener('change', syncUpgradeWorkspacesField);
  document.querySelector('[data-upgrade-confirm]')?.addEventListener('click', () => {
    confirmUpgradeOrder().catch((error) => setErrorStatus(error, 'Kunde inte skapa beställningen.', setUpgradeStatus));
  });
  document.querySelector('[data-upgrade-cancel]')?.addEventListener('click', () => {
    hideUpgradeConfirm();
    setUpgradeStatus('Beställningen avbröts.');
  });
  syncUpgradeWorkspacesField();
}

document.querySelector('[data-plan-next-steps]')?.addEventListener('click', (event) => {
  const button = event.target.closest('[data-select-plan]');
  if (!button) return;
  selectUpgradePlan(button.dataset.selectPlan);
});

const renameWorkspaceForm = document.querySelector('[data-rename-workspace-form]');
const toggleRenameButton = document.querySelector('[data-toggle-rename-workspace]');
if (renameWorkspaceForm && toggleRenameButton) {
  toggleRenameButton.addEventListener('click', () => {
    renameWorkspaceForm.hidden = !renameWorkspaceForm.hidden;
    if (!renameWorkspaceForm.hidden) {
      renameWorkspaceForm.querySelector('input[name="name"]').value = state.workspace?.name || '';
      renameWorkspaceForm.querySelector('input[name="name"]').focus();
    }
  });
  renameWorkspaceForm.addEventListener('submit', renameWorkspace);
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
    refreshWorkspaceData().catch((error) => setErrorStatus(error, 'Kunde inte uppdatera.'));
  });
});

document.addEventListener('submit', (event) => {
  if (event.target.matches('[data-quick-create-form]')) {
    submitQuickCreatePrompt(event);
  }
  if (event.target.matches('[data-workspace-invite-form]')) {
    submitWorkspaceInvite(event);
  }
});

document.addEventListener('click', (event) => {
  const publishButton = event.target.closest('[data-publish-prompt]');
  const unpublishButton = event.target.closest('[data-unpublish-prompt]');
  const editButton = event.target.closest('[data-edit-prompt]');
  const deleteButton = event.target.closest('[data-delete-prompt]');
  const previewButton = event.target.closest('[data-preview-prompt]');
  const previewOrderButton = event.target.closest('[data-preview-order]');
  const revokeButton = event.target.closest('[data-revoke-api-key]');

  const revokeMcpButton = event.target.closest('[data-revoke-mcp-key]');
  const revokeJoinCodeButton = event.target.closest('[data-revoke-join-code]');
  const markInvoicedButton = event.target.closest('[data-mark-invoiced]');
  const markPaidButton = event.target.closest('[data-mark-paid]');
  const activateOrderButton = event.target.closest('[data-activate-order]');
  const downgradeOrderButton = event.target.closest('[data-downgrade-order]');
  const switchWorkspaceButton = event.target.closest('[data-switch-workspace]');
  const quickCreateToggleButton = event.target.closest('[data-quick-create-toggle]');
  const inviteToggleButton = event.target.closest('[data-invite-toggle]');
  const deleteWorkspaceButton = event.target.closest('[data-delete-workspace]');
  const copySecretButton = event.target.closest('[data-copy-secret]');
  const testMcpConnectionButton = event.target.closest('[data-test-mcp-connection]');

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

  if (previewOrderButton) {
    const orderId = previewOrderButton.dataset.previewOrder;
    state.expandedOrderId = state.expandedOrderId === orderId ? null : orderId;
    renderProOrders();
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

  if (markInvoicedButton) {
    markOrderInvoiced(markInvoicedButton.dataset.markInvoiced);
  }

  if (markPaidButton) {
    markOrderPaid(markPaidButton.dataset.markPaid);
  }

  if (activateOrderButton) {
    if (activateOrderButton.dataset.confirm === '1') {
      activateProOrder(activateOrderButton.dataset.activateOrder);
    } else {
      activateOrderButton.dataset.confirm = '1';
      const originalLabel = activateOrderButton.textContent;
      activateOrderButton.textContent = 'Bekräfta aktivering?';
      activateOrderButton.classList.add('is-confirming');
      setTimeout(() => {
        if (activateOrderButton.isConnected) {
          activateOrderButton.dataset.confirm = '0';
          activateOrderButton.textContent = originalLabel;
          activateOrderButton.classList.remove('is-confirming');
        }
      }, 4000);
    }
  }

  if (downgradeOrderButton) {
    if (downgradeOrderButton.dataset.deleteConfirm === '1') {
      downgradeProOrder(downgradeOrderButton.dataset.downgradeOrder);
    } else {
      downgradeOrderButton.dataset.deleteConfirm = '1';
      const originalLabel = downgradeOrderButton.textContent;
      downgradeOrderButton.textContent = 'Bekräfta nedgradering?';
      downgradeOrderButton.classList.add('is-confirming');
      setTimeout(() => {
        if (downgradeOrderButton.isConnected) {
          downgradeOrderButton.dataset.deleteConfirm = '0';
          downgradeOrderButton.textContent = originalLabel;
          downgradeOrderButton.classList.remove('is-confirming');
        }
      }, 4000);
    }
  }

  if (switchWorkspaceButton) {
    switchToWorkspace(switchWorkspaceButton.dataset.switchWorkspace).catch((error) => {
      setErrorStatus(error, 'Kunde inte byta arbetsyta.');
    });
  }

  if (quickCreateToggleButton) {
    const workspaceId = quickCreateToggleButton.dataset.quickCreateToggle;
    state.expandedWorkspaceId = state.expandedWorkspaceId === workspaceId ? null : workspaceId;
    renderWorkspaces();
  }

  if (inviteToggleButton) {
    const workspaceId = inviteToggleButton.dataset.inviteToggle;
    state.expandedInviteWorkspaceId = state.expandedInviteWorkspaceId === workspaceId ? null : workspaceId;
    renderWorkspaces();
  }

  if (deleteWorkspaceButton) {
    deleteWorkspaceFromList(
      deleteWorkspaceButton.dataset.deleteWorkspace,
      deleteWorkspaceButton.dataset.deleteWorkspaceName
    ).catch((error) => {
      setErrorStatus(error, 'Kunde inte radera arbetsytan.');
    });
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

  if (testMcpConnectionButton) {
    const rawKey = document.querySelector('[data-new-mcp-key]')?.textContent;
    if (rawKey) {
      testMcpConnection(rawKey);
    }
  }
});

init().catch((error) => {
  setErrorStatus(error, 'Kunde inte ladda adminytan.');
});
