import { requireSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const CANONICAL_BASE = 'https://app.promptbanken.se';
const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

const state = {
  session: null,
  profile: null
};

const statusElement = document.querySelector('[data-creator-status]');
const loginNeededElement = document.querySelector('[data-creator-login-needed]');
const editorElement = document.querySelector('[data-creator-editor]');
const userEmailElement = document.querySelector('[data-creator-user-email]');
const formElement = document.querySelector('[data-creator-form]');
const publicUrlTextElement = document.querySelector('[data-creator-public-url]');
const publicLinkWrapElement = document.querySelector('[data-creator-public-link-wrap]');
const publicLinkElement = document.querySelector('[data-creator-public-link]');
const statusBadgeElement = document.querySelector('[data-creator-status-badge]');
const eligibleElement = document.querySelector('[data-creator-eligible]');
const lockWarningElement = document.querySelector('[data-creator-lock-warning]');
const publishButton = document.querySelector('[data-creator-publish]');
const unpublishButton = document.querySelector('[data-creator-unpublish]');

function setStatus(message, isError = false) {
  if (!statusElement) return;
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

// Samma regel som isProfileIndexable() i scripts/creator-page-lib.mjs --
// håll dessa två i synk om tröskeln ändras där. Det Node-riktade skriptet
// importeras inte hit: den här sidan är en Vite-bundlad webbläsarmodul och
// regeln är trivial nog att duplicera säkert (samma mönster som
// isIndexable() i adminPackageSeo.js).
function isProfileIndexable(profile) {
  const hasText = (value) => typeof value === 'string' && value.trim() !== '';
  return hasText(profile?.display_name) && hasText(profile?.bio_short);
}

// Adressen valideras alltid mot samma format som databasens
// creator_profiles_slug_format-constraint innan den används i en URL.
function publicUrlFor(slug) {
  if (typeof slug !== 'string') return null;
  const trimmed = slug.trim();
  if (!SLUG_PATTERN.test(trimmed)) return null;
  return `${CANONICAL_BASE}/creator/${trimmed}/`;
}

function fillForm(profile) {
  if (!formElement) return;
  formElement.elements['display_name'].value = profile?.display_name || '';
  formElement.elements['slug'].value = profile?.slug || '';
  formElement.elements['bio_short'].value = profile?.bio_short || '';
  formElement.elements['bio_long'].value = profile?.bio_long || '';
  formElement.elements['competence_areas'].value = Array.isArray(profile?.competence_areas)
    ? profile.competence_areas.join(', ')
    : '';
  formElement.elements['organisation'].value = profile?.organisation || '';
  formElement.elements['website_url'].value = profile?.website_url || '';
  formElement.elements['linkedin_url'].value = profile?.linkedin_url || '';

  // Adressfältet låses i UI:t när servern har låst det -- ändringar skulle
  // ändå avvisas av upsert-RPC:n, men att låta fältet vara redigerbart
  // skulle antyda att en ändring där faktiskt sparas.
  formElement.elements['slug'].disabled = Boolean(profile?.slug_locked);
}

function renderProfileState(profile) {
  if (statusBadgeElement) {
    statusBadgeElement.textContent = profile
      ? (profile.status === 'published' ? 'Publicerad' : 'Utkast')
      : 'Inget utkast sparat ännu';
  }

  if (eligibleElement) {
    const eligible = isProfileIndexable(profile);
    eligibleElement.textContent = eligible
      ? 'Redo att publiceras: visningsnamn och kort presentation är ifyllda.'
      : 'Fyll i visningsnamn och kort presentation för att kunna publicera.';
    eligibleElement.classList.toggle('is-error', !eligible);
  }

  if (lockWarningElement) {
    lockWarningElement.textContent = profile?.slug_locked
      ? 'Adressen är låst sedan profilen publicerades första gången och kan inte ändras av dig själv.'
      : 'Adressen låses när du publicerar profilen och kan inte ändras av dig själv efteråt.';
  }

  const url = profile?.slug ? publicUrlFor(profile.slug) : null;
  if (publicUrlTextElement) {
    publicUrlTextElement.textContent = url
      ? url
      : `${CANONICAL_BASE}/creator/<adress>/ (sätts när du sparar profilen första gången)`;
  }

  const isPublished = profile?.status === 'published';
  if (publicLinkWrapElement) publicLinkWrapElement.hidden = !(isPublished && url);
  if (publicLinkElement && url) publicLinkElement.href = url;

  if (publishButton) publishButton.hidden = !profile || isPublished;
  if (unpublishButton) unpublishButton.hidden = !profile || !isPublished;
}

async function loadProfile() {
  setStatus('Laddar profil...');
  const { data, error } = await supabase.rpc('get_my_creator_profile');
  if (error) throw error;

  state.profile = (Array.isArray(data) && data[0]) || null;
  fillForm(state.profile);
  renderProfileState(state.profile);
  setStatus(state.profile ? 'Profil laddad.' : 'Ingen profil sparad ännu. Fyll i formuläret och spara.');
}

async function saveForm(event) {
  event.preventDefault();
  if (!formElement) return;

  const formData = new FormData(formElement);
  const displayName = String(formData.get('display_name') || '').trim();
  if (!displayName) {
    setStatus('Visningsnamn krävs.', true);
    return;
  }

  // Tomma fält skickas som '' (och kompetensområden som []), inte null --
  // RPC:n skiljer "utelämnad" (null, behåll befintligt värde) från
  // "rensad" (tom sträng/array, skriv över med tomt). Skickar vi null här
  // kan användaren aldrig rensa ett redan ifyllt fält via UI:t.
  const slug = String(formData.get('slug') || '').trim();
  const bioShort = String(formData.get('bio_short') || '').trim();
  const bioLong = String(formData.get('bio_long') || '').trim();
  const competenceRaw = String(formData.get('competence_areas') || '').trim();
  const competenceAreas = competenceRaw
    ? competenceRaw.split(',').map((area) => area.trim()).filter(Boolean)
    : [];
  const organisation = String(formData.get('organisation') || '').trim();
  const websiteUrl = String(formData.get('website_url') || '').trim();
  const linkedinUrl = String(formData.get('linkedin_url') || '').trim();

  setStatus('Sparar...');
  try {
    const { data, error } = await supabase.rpc('upsert_my_creator_profile', {
      p_display_name: displayName,
      p_slug: slug,
      p_bio_short: bioShort,
      p_bio_long: bioLong,
      p_competence_areas: competenceAreas,
      p_organisation: organisation,
      p_website_url: websiteUrl,
      p_linkedin_url: linkedinUrl
    });

    if (error) throw error;

    state.profile = data;
    fillForm(state.profile);
    renderProfileState(state.profile);
    setStatus('Sparat.');
  } catch (error) {
    // RPC-felen är redan på svenska -- visa dem som de är.
    setStatus(error.message || 'Kunde inte spara.', true);
  }
}

async function publishProfile() {
  setStatus('Publicerar...');
  try {
    const { data, error } = await supabase.rpc('publish_my_creator_profile');
    if (error) throw error;

    state.profile = data;
    fillForm(state.profile);
    renderProfileState(state.profile);
    setStatus('Profilen är publicerad.');
  } catch (error) {
    setStatus(error.message || 'Kunde inte publicera.', true);
  }
}

async function unpublishProfile() {
  setStatus('Avpublicerar...');
  try {
    const { data, error } = await supabase.rpc('unpublish_my_creator_profile');
    if (error) throw error;

    state.profile = data;
    fillForm(state.profile);
    renderProfileState(state.profile);
    setStatus('Profilen är avpublicerad (utkast).');
  } catch (error) {
    setStatus(error.message || 'Kunde inte avpublicera.', true);
  }
}

async function logout() {
  await supabase.auth.signOut();
  window.location.replace('login.html');
}

async function init() {
  if (!requireSupabaseConfig(statusElement)) return;

  const session = await requireSession();
  if (!session) {
    // requireSession() har redan påbörjat en redirect till login.html.
    // Visa ändå ett meddelande med länk i fall omdirigeringen dröjer.
    if (loginNeededElement) loginNeededElement.hidden = false;
    if (editorElement) editorElement.hidden = true;
    setStatus('Du är inte inloggad.', true);
    return;
  }

  state.session = session;
  if (userEmailElement) userEmailElement.textContent = session.user.email || '-';
  if (editorElement) editorElement.hidden = false;

  await loadProfile();
}

formElement?.addEventListener('submit', (event) => {
  saveForm(event).catch((error) => setStatus(error.message || 'Kunde inte spara.', true));
});
publishButton?.addEventListener('click', () => {
  publishProfile().catch((error) => setStatus(error.message || 'Kunde inte publicera.', true));
});
unpublishButton?.addEventListener('click', () => {
  unpublishProfile().catch((error) => setStatus(error.message || 'Kunde inte avpublicera.', true));
});
document.querySelector('[data-creator-logout]')?.addEventListener('click', logout);

init().catch((error) => setStatus(error.message || 'Kunde inte ladda profilytan.', true));
