import { getCurrentSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const PENDING_TOKEN_KEY = 'promptbankenPendingInviteToken';

const statusElement = document.querySelector('[data-invite-status]');
const actionsElement = document.querySelector('[data-invite-actions]');

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

function getTokenFromUrl() {
  return new URLSearchParams(window.location.search).get('token');
}

async function redeemInvite(token) {
  const { data, error } = await supabase.rpc('redeem_pro_invite', { p_token: token });

  if (error) {
    setStatus(error.message || 'Kunde inte lösa in inbjudan.', true);
    return;
  }

  const result = Array.isArray(data) ? data[0] : data;
  const expires = result?.plan_expires_at
    ? new Date(result.plan_expires_at).toLocaleDateString('sv-SE')
    : null;

  setStatus(
    expires
      ? `Klart! Pro är aktiverat till och med ${expires}.`
      : 'Klart! Pro är aktiverat på ditt konto.'
  );
  actionsElement.hidden = false;
}

async function init() {
  if (!requireSupabaseConfig(statusElement)) {
    return;
  }

  let token = getTokenFromUrl();

  if (token) {
    sessionStorage.setItem(PENDING_TOKEN_KEY, token);
  } else {
    token = sessionStorage.getItem(PENDING_TOKEN_KEY);
  }

  if (!token) {
    setStatus('Ingen inbjudningslänk hittades. Kontrollera att du klickade på hela länken.', true);
    return;
  }

  const session = await getCurrentSession();
  if (!session) {
    setStatus('Logga in eller skapa ett konto för att lösa in din Pro-inbjudan...');
    window.location.assign('login.html?redirect=invite.html');
    return;
  }

  sessionStorage.removeItem(PENDING_TOKEN_KEY);
  await redeemInvite(token);
}

init().catch((error) => {
  setStatus(error.message || 'Ett oväntat fel uppstod.', true);
});
