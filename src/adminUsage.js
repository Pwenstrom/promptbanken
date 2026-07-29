import { requireSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const state = {
  periodDays: 30,
  summary: null,
  prompts: [],
  packages: [],
  errors: [],
  search: null,
  user: null
};

const statusElement = document.querySelector('[data-admin-status]');
const dashboardElement = document.querySelector('[data-admin-dashboard]');
const deniedElement = document.querySelector('[data-admin-denied]');
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
  return new Date(value).toLocaleString('sv-SE', { dateStyle: 'short', timeStyle: 'short' });
}

function metric(summary, key) {
  return Number(summary?.metrics?.[key] || 0);
}

function renderSummary() {
  const el = document.querySelector('[data-summary-cards]');
  if (!el) return;
  const cards = [
    ['Webbvisningar', metric(state.summary, 'web_prompt_views'), 'Promptdetaljer öppnade'],
    ['Webbkopior', metric(state.summary, 'web_prompt_copies'), 'Kopierade prompttexter'],
    ['MCP-hämtningar', metric(state.summary, 'mcp_prompt_gets'), 'get_prompt via öppen MCP'],
    ['Paketaktivitet', metric(state.summary, 'package_activity'), 'Webb och MCP'],
    ['Tomma sökningar', metric(state.summary, 'searches_empty'), 'Saknade behov'],
    ['Fel/not found', metric(state.summary, 'errors_or_not_found'), 'Åtgärdssignaler']
  ];
  el.innerHTML = cards.map(([label, value, hint]) => `
    <article>
      <strong>${value}</strong>
      <span>${escapeHtml(label)}</span>
      <small>${escapeHtml(hint)}</small>
    </article>
  `).join('');
}

function renderPromptUsage() {
  const el = document.querySelector('[data-prompt-usage]');
  if (!el) return;
  el.innerHTML = state.prompts.length
    ? state.prompts.map((row) => `
      <tr>
        <td>${escapeHtml(row.prompt_slug)}</td>
        <td>${row.web_views}</td>
        <td>${row.web_copies}</td>
        <td>${row.mcp_gets}</td>
        <td>${row.not_found}</td>
        <td>${formatDate(row.last_event_at)}</td>
      </tr>
    `).join('')
    : '<tr><td colspan="6">Ingen promptstatistik för vald period.</td></tr>';
}

function renderPackageUsage() {
  const el = document.querySelector('[data-package-usage]');
  if (!el) return;
  el.innerHTML = state.packages.length
    ? state.packages.map((row) => `
      <tr>
        <td>${escapeHtml(row.package_slug)}</td>
        <td>${row.web_views}</td>
        <td>${row.mcp_gets}</td>
        <td>${row.package_prompt_lists}</td>
        <td>${row.not_found}</td>
        <td>${formatDate(row.last_event_at)}</td>
      </tr>
    `).join('')
    : '<tr><td colspan="6">Ingen paketstatistik för vald period.</td></tr>';
}

function renderErrors() {
  const el = document.querySelector('[data-usage-errors]');
  if (!el) return;
  el.innerHTML = state.errors.length
    ? state.errors.map((row) => `
      <tr>
        <td>${escapeHtml(row.source)}</td>
        <td>${escapeHtml(row.event_type)}</td>
        <td>${escapeHtml(row.outcome)}</td>
        <td>${escapeHtml(row.prompt_slug || '-')}</td>
        <td>${escapeHtml(row.package_slug || '-')}</td>
        <td>${row.count}</td>
        <td>${formatDate(row.last_event_at)}</td>
      </tr>
    `).join('')
    : '<tr><td colspan="7">Inga fel eller tomma utfall för vald period.</td></tr>';
}

function renderSearchFeedback() {
  const el = document.querySelector('[data-search-feedback]');
  if (!el) return;
  const searches = Number(state.search?.searches || 0);
  const empty = Number(state.search?.empty_searches || 0);
  const rate = searches ? Math.round((empty / searches) * 100) : 0;
  el.innerHTML = `
    <div class="library-insight-grid">
      <article><strong>${searches}</strong><span>Sökningar</span></article>
      <article><strong>${empty}</strong><span>Utan träff</span></article>
      <article><strong>${rate}%</strong><span>Tomma sökningar</span></article>
    </div>
  `;
}

function renderMcpStatus() {
  const el = document.querySelector('[data-mcp-status]');
  if (!el) return;
  el.innerHTML = `
    <div class="library-insight-grid">
      <article><strong>${formatDate(state.summary?.last_open_mcp_success_at)}</strong><span>Senaste lyckade öppna MCP-event</span></article>
      <article><strong>${Number(state.summary?.totals?.open_mcp || 0)}</strong><span>Öppna MCP-events</span></article>
      <article><strong>${Number(state.summary?.totals?.web || 0)}</strong><span>Webbevents</span></article>
    </div>
  `;
}

function renderAll() {
  renderSummary();
  renderPromptUsage();
  renderPackageUsage();
  renderErrors();
  renderSearchFeedback();
  renderMcpStatus();
}

async function loadDashboard() {
  const requestId = ++latestRequestId;
  setStatus('Laddar statistik...');
  const days = state.periodDays;
  try {
    const [summary, prompts, packages, errors, search] = await Promise.all([
      supabase.rpc('get_library_usage_summary', { p_days: days }),
      supabase.rpc('get_library_prompt_usage', { p_days: days, p_limit: 50 }),
      supabase.rpc('get_library_package_usage', { p_days: days, p_limit: 50 }),
      supabase.rpc('get_library_usage_errors', { p_days: days, p_limit: 50 }),
      supabase.rpc('get_library_search_feedback', { p_days: days, p_limit: 50 })
    ]);

    if (requestId !== latestRequestId) return;

    const failed = [summary, prompts, packages, errors, search].find((result) => result.error);
    if (failed) {
      if (/plattformsägare|platform/i.test(failed.error.message || '')) {
        dashboardElement.hidden = true;
        deniedElement.hidden = false;
        setStatus('Ingen åtkomst.', true);
        return;
      }
      throw failed.error;
    }

    state.summary = summary.data;
    state.prompts = prompts.data || [];
    state.packages = packages.data || [];
    state.errors = errors.data || [];
    state.search = search.data;
    deniedElement.hidden = true;
    dashboardElement.hidden = false;
    setStatus(`Visar anonym statistik för ${days} dagar.`);
    renderAll();
  } catch (error) {
    if (requestId === latestRequestId) throw error;
  }
}

function downloadBlob(filename, content, type) {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

function exportJson() {
  downloadBlob(
    `promptbanken-statistik-${state.periodDays}d.json`,
    JSON.stringify({
      summary: state.summary,
      prompts: state.prompts,
      packages: state.packages,
      errors: state.errors,
      search: state.search
    }, null, 2),
    'application/json;charset=utf-8'
  );
}

function exportCsv() {
  const rows = [
    ['type', 'slug', 'web_views', 'web_copies', 'mcp_gets', 'not_found', 'last_event_at'],
    ...state.prompts.map((row) => ['prompt', row.prompt_slug, row.web_views, row.web_copies, row.mcp_gets, row.not_found, row.last_event_at]),
    ...state.packages.map((row) => ['package', row.package_slug, row.web_views, '', row.mcp_gets, row.not_found, row.last_event_at])
  ];
  const csv = rows.map((row) => row.map((cell) => `"${String(cell ?? '').replaceAll('"', '""')}"`).join(',')).join('\n');
  downloadBlob(`promptbanken-statistik-${state.periodDays}d.csv`, csv, 'text/csv;charset=utf-8');
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
  document.querySelector('[data-user-email]').textContent = session.user.email || '-';
  await loadDashboard();
}

document.querySelector('[data-logout]')?.addEventListener('click', logout);
document.querySelector('[data-refresh]')?.addEventListener('click', () => loadDashboard().catch((error) => setStatus(error.message || 'Kunde inte ladda statistik.', true)));
document.querySelector('[data-export-json]')?.addEventListener('click', exportJson);
document.querySelector('[data-export-csv]')?.addEventListener('click', exportCsv);

document.querySelectorAll('[data-period]').forEach((button) => {
  button.addEventListener('click', () => {
    state.periodDays = Number(button.dataset.period);
    document.querySelectorAll('[data-period]').forEach((item) => item.classList.toggle('active', item === button));
    loadDashboard().catch((error) => setStatus(error.message || 'Kunde inte ladda statistik.', true));
  });
});

init().catch((error) => setStatus(error.message || 'Kunde inte ladda adminytan.', true));
