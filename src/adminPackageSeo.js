import { requireSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const state = {
  packages: [],
  selectedId: null,
  user: null
};

const statusElement = document.querySelector('[data-seo-status]');
const deniedElement = document.querySelector('[data-seo-denied]');
const editorElement = document.querySelector('[data-seo-editor]');
const selectElement = document.querySelector('[data-seo-package-select]');
const formElement = document.querySelector('[data-seo-form]');
const indexableStatusElement = document.querySelector('[data-seo-indexable-status]');
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

// Samma regel som isIndexable() i scripts/catalog-page-lib.mjs -- håll
// dessa två i synk om tröskeln ändras där.
function isIndexable(pkg) {
  if (pkg?.is_indexable === true) return true;
  if (pkg?.is_indexable === false) return false;
  const hasIntro = typeof pkg?.intro_text === 'string' && pkg.intro_text.trim() !== '';
  const promptCount = Number(pkg?.prompt_count || 0);
  return hasIntro && promptCount >= 3;
}

function selectedPackage() {
  return state.packages.find((pkg) => pkg.id === state.selectedId) || null;
}

function renderPackageOptions() {
  if (!selectElement) return;
  selectElement.innerHTML = state.packages.length
    ? state.packages.map((pkg) => `<option value="${escapeHtml(pkg.id)}">${escapeHtml(pkg.title || pkg.slug)}</option>`).join('')
    : '<option value="">Inga publicerade paket</option>';
}

function renderIndexableStatus(pkg) {
  if (!indexableStatusElement) return;
  const indexable = isIndexable(pkg);
  indexableStatusElement.textContent = `Indexerbar: ${indexable ? 'ja' : 'nej'}`;
  indexableStatusElement.classList.toggle('is-error', !indexable);
}

function indexableModeFor(pkg) {
  if (pkg?.is_indexable === true) return 'always';
  if (pkg?.is_indexable === false) return 'never';
  return 'auto';
}

function renderForm() {
  const pkg = selectedPackage();
  if (!formElement || !pkg) {
    if (editorElement) editorElement.hidden = true;
    return;
  }
  if (editorElement) editorElement.hidden = false;

  formElement.elements['problem_text'].value = pkg.problem_text || '';
  formElement.elements['when_to_use'].value = pkg.when_to_use || '';
  formElement.elements['outcome_text'].value = pkg.outcome_text || '';
  formElement.elements['area'].value = pkg.area || '';
  formElement.elements['tags'].value = Array.isArray(pkg.tags) ? pkg.tags.join(', ') : '';
  formElement.elements['is_indexable_mode'].value = indexableModeFor(pkg);

  renderIndexableStatus(pkg);
}

async function loadPromptCount(slug) {
  const { data, error } = await supabase.rpc('list_published_package_prompts', { p_package_slug: slug });
  if (error) return 0;
  return (data || []).length;
}

async function loadPackages() {
  const requestId = ++latestRequestId;
  setStatus('Laddar paket...');
  const { data, error } = await supabase.rpc('list_published_packages');
  if (requestId !== latestRequestId) return;

  if (error) {
    if (/plattformsägare|platform/i.test(error.message || '')) {
      if (editorElement) editorElement.hidden = true;
      if (deniedElement) deniedElement.hidden = false;
      setStatus('Ingen åtkomst.', true);
      return;
    }
    throw error;
  }

  if (deniedElement) deniedElement.hidden = true;

  // Samma promptantal som generatorn (scripts/generate-catalog-pages.mjs)
  // använder för isIndexable(pkg, promptCount): antal rader från
  // list_published_package_prompts, inte ett fält på paketet självt.
  const packages = data || [];
  const promptCounts = await Promise.all(packages.map((pkg) => loadPromptCount(pkg.slug)));
  if (requestId !== latestRequestId) return;

  state.packages = packages.map((pkg, index) => ({ ...pkg, prompt_count: promptCounts[index] }));
  renderPackageOptions();

  if (!state.selectedId && state.packages.length) {
    state.selectedId = state.packages[0].id;
  }
  if (selectElement) selectElement.value = state.selectedId || '';
  renderForm();
  setStatus(state.packages.length ? `Visar ${state.packages.length} publicerade paket.` : 'Inga publicerade paket hittades.');
}

async function saveForm(event) {
  event.preventDefault();
  const pkg = selectedPackage();
  if (!pkg) return;

  // Tomma fält skickas som '' / [] (inte null) -- RPC:erna använder
  // coalesce(p_x, existing) för att skilja "utelämnad" (null, behåll
  // befintligt värde) från "rensad" (tom sträng/array, skriv över med
  // tomt). Skickar vi null här kan admin aldrig rensa ett fält via UI:t.
  const formData = new FormData(formElement);
  const problemText = String(formData.get('problem_text') || '').trim();
  const whenToUse = String(formData.get('when_to_use') || '').trim();
  const outcomeText = String(formData.get('outcome_text') || '').trim();
  const area = String(formData.get('area') || '').trim();
  const tagsRaw = String(formData.get('tags') || '').trim();
  const tags = tagsRaw ? tagsRaw.split(',').map((tag) => tag.trim()).filter(Boolean) : [];
  const mode = String(formData.get('is_indexable_mode') || 'auto');
  const isIndexableValue = mode === 'always' ? true : mode === 'never' ? false : null;

  setStatus('Sparar...');
  try {
    const [{ error: variantError }, { error: metadataError }] = await Promise.all([
      supabase.rpc('upsert_catalog_package_variant', {
        p_package_id: pkg.id,
        p_context_key: 'generell',
        p_title: pkg.title,
        p_summary: pkg.summary,
        p_intro_text: pkg.intro_text,
        p_audience_label: pkg.audience_label,
        p_problem_text: problemText,
        p_when_to_use: whenToUse,
        p_outcome_text: outcomeText
      }),
      supabase.rpc('upsert_catalog_package_metadata', {
        p_package_id: pkg.id,
        p_area: area,
        p_tags: tags,
        p_is_indexable: isIndexableValue,
        p_is_indexable_provided: true
      })
    ]);

    if (variantError) throw variantError;
    if (metadataError) throw metadataError;

    setStatus('Sparat.');
    await loadPackages();
  } catch (error) {
    setStatus(error.message || 'Kunde inte spara.', true);
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
  const userEmailElement = document.querySelector('[data-seo-user-email]');
  if (userEmailElement) userEmailElement.textContent = session.user.email || '-';
  await loadPackages();
}

selectElement?.addEventListener('change', () => {
  state.selectedId = selectElement.value || null;
  renderForm();
});
formElement?.addEventListener('submit', (event) => saveForm(event).catch((error) => setStatus(error.message || 'Kunde inte spara.', true)));
document.querySelector('[data-seo-refresh]')?.addEventListener('click', () => loadPackages().catch((error) => setStatus(error.message || 'Kunde inte ladda paket.', true)));
document.querySelector('[data-seo-logout]')?.addEventListener('click', logout);

init().catch((error) => setStatus(error.message || 'Kunde inte ladda adminytan.', true));
