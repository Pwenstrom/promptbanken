import { getRedirectTarget, redirectIfAuthenticated, requireSupabaseConfig } from './auth.js';
import { supabase } from './supabaseClient.js';

const form = document.querySelector('[data-login-form]');
const emailInput = document.querySelector('[data-login-email]');
const passwordInput = document.querySelector('[data-login-password]');
const statusElement = document.querySelector('[data-login-status]');
const submitButton = document.querySelector('[data-auth-submit]');
const modeButtons = document.querySelectorAll('[data-auth-mode]');
let authMode = 'login';

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.classList.toggle('is-error', isError);
}

async function handleLogin(event) {
  event.preventDefault();

  if (!requireSupabaseConfig(statusElement)) {
    return;
  }

  setStatus(authMode === 'signup' ? 'Skapar free-konto...' : 'Loggar in...');

  const credentials = {
    email: emailInput.value.trim(),
    password: passwordInput.value
  };

  const { data, error } = authMode === 'signup'
    ? await supabase.auth.signUp(credentials)
    : await supabase.auth.signInWithPassword(credentials);

  if (error) {
    setStatus(error.message || 'Åtgärden misslyckades.', true);
    return;
  }

  if (authMode === 'signup') {
    if (!data.session) {
      setStatus('Kontot är skapat. Bekräfta e-posten och logga sedan in.');
      return;
    }

    const { error: workspaceError } = await supabase.rpc('ensure_personal_workspace');
    if (workspaceError) {
      setStatus(workspaceError.message || 'Kontot skapades men privat workspace kunde inte skapas.', true);
      return;
    }
  }

  window.location.assign(getRedirectTarget());
}

function setAuthMode(nextMode) {
  authMode = nextMode;
  modeButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.authMode === authMode);
  });
  submitButton.textContent = authMode === 'signup' ? 'Skapa free-konto' : 'Logga in';
  passwordInput.autocomplete = authMode === 'signup' ? 'new-password' : 'current-password';
  setStatus('');
}

if (form) {
  form.addEventListener('submit', handleLogin);
}

modeButtons.forEach((button) => {
  button.addEventListener('click', () => setAuthMode(button.dataset.authMode));
});

if (requireSupabaseConfig(statusElement)) {
  redirectIfAuthenticated(getRedirectTarget()).catch((error) => {
    setStatus(error.message || 'Kunde inte kontrollera session.', true);
  });
}
