import { getCurrentSession, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const PENDING_TOKEN_KEY = 'promptbankenPendingTeamToken';

const statusElement = document.querySelector('[data-team-invite-status]');
const actionsElement = document.querySelector('[data-team-invite-actions]');

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

function getTokenFromUrl() {
  return new URLSearchParams(window.location.search).get('team_token');
}

async function redeemJoinCode(token) {
  const { error } = await supabase.rpc('redeem_org_join_code', { p_token: token });

  if (error) {
    setStatus(error.message || 'Kunde inte gå med i teamet.', true);
    return;
  }

  setStatus('Klart! Du är nu medlem i arbetsytan.');
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
    setStatus('Ingen join-länk hittades. Kontrollera att du klickade på hela länken.', true);
    return;
  }

  const session = await getCurrentSession();
  if (!session) {
    setStatus('Logga in eller skapa ett konto för att gå med i teamet...');
    window.location.assign('login.html?redirect=team-invite.html');
    return;
  }

  sessionStorage.removeItem(PENDING_TOKEN_KEY);
  await redeemJoinCode(token);
}

init().catch((error) => {
  setStatus(error.message || 'Ett oväntat fel uppstod.', true);
});
