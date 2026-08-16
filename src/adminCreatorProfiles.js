import { requireSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

const state = {
  profiles: [],
  user: null
};

const statusElement = document.querySelector('[data-creator-admin-status]');
const deniedElement = document.querySelector('[data-creator-admin-denied]');
const listElement = document.querySelector('[data-creator-admin-list]');
const tableBodyElement = document.querySelector('[data-creator-admin-table-body]');
let latestRequestId = 0;

function setStatus(message, isError = false) {
  if (!statusElement) return;
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function formatDate(value) {
  if (!value) return '-';
  return new Date(value).toLocaleDateString('sv-SE');
}

// RPC:erna admin_unpublish_creator_profile och
// admin_update_creator_profile_slug vägrar för icke-plattformsägare med ett
// svenskt fel ("Endast plattformsägare kan hantera creator-profiler.") --
// visa det som det är, samma mönster som isIndexable-felhanteringen i
// adminPackageSeo.js.
function handleActionError(error) {
  const message = error?.message || 'Kunde inte genomföra åtgärden.';
  if (/plattformsägare|platform/i.test(message)) {
    if (deniedElement) deniedElement.hidden = false;
  }
  setStatus(message, true);
}

// published_at ändras INTE av admin_unpublish_creator_profile/
// unpublish_my_creator_profile -- den behåller senaste publiceringsdatum
// som historik. Visa därför status.text separat, annars ser en avpublicerad
// (draft) profil ut som fortfarande publicerad i listan.
function statusLabel(status) {
  return status === 'published' ? 'Publicerad' : 'Utkast';
}

function renderRow(profile) {
  const hasUserId = Boolean(profile.user_id);
  const disabledAttr = hasUserId ? '' : 'disabled';
  return `
    <tr data-user-id="${escapeHtml(profile.user_id || '')}">
      <td>${escapeHtml(profile.display_name)}</td>
      <td>${escapeHtml(profile.slug)}</td>
      <td>${escapeHtml(statusLabel(profile.status))}</td>
      <td>${escapeHtml(formatDate(profile.published_at))}</td>
      <td>
        <div class="workspace-form-actions">
          <input type="text" class="creator-admin-slug-input" value="${escapeHtml(profile.slug)}" ${disabledAttr}>
          <button type="button" data-change-slug ${disabledAttr}>Spara adress</button>
          <button type="button" data-unpublish ${disabledAttr}>Avpublicera</button>
        </div>
      </td>
    </tr>
  `;
}

function renderList() {
  if (!tableBodyElement) return;
  tableBodyElement.innerHTML = state.profiles.length
    ? state.profiles.map(renderRow).join('')
    : '<tr><td colspan="5">Inga creator-profiler.</td></tr>';
}

async function loadProfiles() {
  const requestId = ++latestRequestId;
  setStatus('Laddar creator-profiler...');
  // admin_list_creator_profiles() är en moderationsvy: den visar alla
  // profiler (draft + published) och inkluderar user_id direkt, till
  // skillnad från den publika list_published_creator_profiles() -- se
  // supabase/migrations/20260816090000_creator_profiles.sql.
  const { data, error } = await supabase.rpc('admin_list_creator_profiles');
  if (requestId !== latestRequestId) return;

  if (error) {
    if (/plattformsägare|platform/i.test(error.message || '')) {
      if (listElement) listElement.hidden = true;
      if (deniedElement) deniedElement.hidden = false;
      setStatus('Ingen åtkomst.', true);
      return;
    }
    throw error;
  }

  if (deniedElement) deniedElement.hidden = true;
  if (listElement) listElement.hidden = false;

  state.profiles = data || [];
  renderList();

  setStatus(state.profiles.length ? `Visar ${state.profiles.length} creator-profiler.` : 'Inga creator-profiler.');
}

async function unpublish(userId) {
  if (!userId) return;
  setStatus('Avpublicerar...');
  try {
    const { error } = await supabase.rpc('admin_unpublish_creator_profile', { p_user_id: userId });
    if (error) throw error;
    setStatus('Profilen avpublicerad.');
    await loadProfiles();
  } catch (error) {
    handleActionError(error);
  }
}

async function changeSlug(userId, newSlug) {
  if (!userId) return;
  const trimmed = String(newSlug || '').trim();
  if (!SLUG_PATTERN.test(trimmed)) {
    setStatus('Ogiltig adress. Använd gemener, siffror och bindestreck.', true);
    return;
  }
  setStatus('Sparar adress...');
  try {
    const { error } = await supabase.rpc('admin_update_creator_profile_slug', {
      p_user_id: userId,
      p_slug: trimmed
    });
    if (error) throw error;
    setStatus('Adressen uppdaterad.');
    await loadProfiles();
  } catch (error) {
    handleActionError(error);
  }
}

async function logout() {
  await supabase.auth.signOut();
  window.location.replace('login.html');
}

async function init() {
  if (!requireSupabaseConfig(statusElement)) return;
  const session = await requireSession();
  if (!session) return;
  state.user = session.user;
  await loadProfiles();
}

tableBodyElement?.addEventListener('click', (event) => {
  const row = event.target.closest('tr[data-user-id]');
  if (!row) return;
  const userId = row.getAttribute('data-user-id');

  if (event.target.closest('[data-unpublish]')) {
    unpublish(userId).catch((error) => setStatus(error.message || 'Kunde inte avpublicera.', true));
    return;
  }

  if (event.target.closest('[data-change-slug]')) {
    const input = row.querySelector('.creator-admin-slug-input');
    changeSlug(userId, input ? input.value : '').catch((error) => setStatus(error.message || 'Kunde inte spara adressen.', true));
  }
});
document.querySelector('[data-creator-admin-refresh]')?.addEventListener('click', () => loadProfiles().catch((error) => setStatus(error.message || 'Kunde inte ladda creator-profiler.', true)));
document.querySelector('[data-creator-admin-logout]')?.addEventListener('click', logout);

init().catch((error) => setStatus(error.message || 'Kunde inte ladda adminytan.', true));
