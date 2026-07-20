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

  setStatus('Loggar in...');

  const credentials = {
    email: emailInput.value.trim(),
    password: passwordInput.value
  };

  if (authMode === 'reset') {
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(credentials.email);
    if (resetError) {
      setStatus(resetError.message || 'Kunde inte skicka återställningslänk.', true);
    } else {
      setStatus('Återställningslänk skickad — kolla din e-post.');
    }
    return;
  }

  const { error } = await supabase.auth.signInWithPassword(credentials);

  if (error) {
    setStatus(error.message || 'Åtgärden misslyckades.', true);
    return;
  }

  window.location.assign(getRedirectTarget());
}

function setAuthMode(nextMode) {
  authMode = nextMode;
  modeButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.authMode === authMode);
  });
  const passwordField = document.querySelector('[data-password-field]');
  if (authMode === 'reset') {
    submitButton.textContent = 'Skicka återställningslänk';
    passwordInput.required = false;
    if (passwordField) passwordField.hidden = true;
  } else {
    submitButton.textContent = 'Logga in';
    passwordInput.required = true;
    if (passwordField) passwordField.hidden = false;
    passwordInput.autocomplete = 'current-password';
  }
  setStatus('');
}

if (form) {
  form.addEventListener('submit', handleLogin);
}

const googleButton = document.querySelector('[data-google-signin]');
if (googleButton) {
  googleButton.addEventListener('click', async () => {
    if (!requireSupabaseConfig(statusElement)) return;
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin + '/admin.html' }
    });
    if (error) setStatus(error.message || 'Kunde inte starta Google-inloggning.', true);
  });
}

modeButtons.forEach((button) => {
  button.addEventListener('click', () => setAuthMode(button.dataset.authMode));
});

if (requireSupabaseConfig(statusElement)) {
  redirectIfAuthenticated(getRedirectTarget()).catch((error) => {
    setStatus(error.message || 'Kunde inte kontrollera session.', true);
  });
}
