import { getCurrentSession, requireSupabaseConfig } from './auth.js';
import { buildConsentLoginUrl, decideAuthorization, loadAuthorizationRequest } from './oauthConsentFlow.js';
import { supabase } from './supabaseClient.js';

const titleElement = document.querySelector('#consent-title');
const loadingElement = document.querySelector('[data-consent-loading]');
const contentElement = document.querySelector('[data-consent-content]');
const clientElement = document.querySelector('[data-consent-client]');
const scopesElement = document.querySelector('[data-consent-scopes]');
const statusElement = document.querySelector('[data-consent-status]');
const approveButton = document.querySelector('[data-consent-approve]');
const denyButton = document.querySelector('[data-consent-deny]');

const scopeLabels = {
  openid: 'Bekräfta vilken användare du är',
  email: 'Se e-postadressen för ditt konto',
  profile: 'Se namn och grundläggande profiluppgifter',
  phone: 'Se telefonnumret för ditt konto'
};

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

function setBusy(isBusy) {
  approveButton.disabled = isBusy;
  denyButton.disabled = isBusy;
}

function renderScopes(scopes) {
  scopesElement.replaceChildren();
  const visibleScopes = scopes.length ? scopes : ['openid'];
  visibleScopes.forEach((scope) => {
    const item = document.createElement('li');
    item.textContent = scopeLabels[scope] || `Begärd behörighet: ${scope}`;
    scopesElement.append(item);
  });
}

async function handleDecision(decision) {
  const authorizationId = new URLSearchParams(window.location.search).get('authorization_id');
  setBusy(true);
  setStatus(decision === 'approve' ? 'Godkänner anslutningen…' : 'Nekar anslutningen…');

  try {
    const redirectUrl = await decideAuthorization(supabase.auth.oauth, authorizationId, decision);
    window.location.assign(redirectUrl);
  } catch (error) {
    setStatus(error.message || 'Beslutet kunde inte sparas. Försök igen.', true);
    setBusy(false);
  }
}

async function initializeConsent() {
  const authorizationId = new URLSearchParams(window.location.search).get('authorization_id');
  if (!authorizationId) {
    loadingElement.hidden = true;
    titleElement.textContent = 'Ogiltig anslutningslänk';
    setStatus('Länken saknar den OAuth-förfrågan som behövs. Starta anslutningen på nytt från AI-tjänsten.', true);
    return;
  }

  if (!requireSupabaseConfig(statusElement)) {
    loadingElement.hidden = true;
    return;
  }

  try {
    const session = await getCurrentSession();
    if (!session) {
      window.location.replace(buildConsentLoginUrl(authorizationId, window.location.origin));
      return;
    }

    const request = await loadAuthorizationRequest(supabase.auth.oauth, authorizationId);
    if (request.kind === 'redirect') {
      window.location.replace(request.redirectUrl);
      return;
    }

    clientElement.textContent = request.clientName;
    titleElement.textContent = `Anslut ${request.clientName}?`;
    renderScopes(request.scopes);
    loadingElement.hidden = true;
    contentElement.hidden = false;
  } catch (error) {
    loadingElement.hidden = true;
    titleElement.textContent = 'Anslutningen kunde inte öppnas';
    setStatus(error.message || 'OAuth-förfrågan är ogiltig eller har gått ut.', true);
  }
}

approveButton.addEventListener('click', () => handleDecision('approve'));
denyButton.addEventListener('click', () => handleDecision('deny'));
initializeConsent();
