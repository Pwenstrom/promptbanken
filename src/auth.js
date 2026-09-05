import { hasSupabaseConfig, supabase } from './supabaseClient.js';
import { parseSafeAuthRedirect } from './authRedirect.js';

export function requireSupabaseConfig(statusElement) {
  if (hasSupabaseConfig) {
    return true;
  }

  if (statusElement) {
    statusElement.textContent = 'Supabase saknar lokal konfiguration. Kontrollera .env.local.';
    statusElement.classList.add('is-error');
  }

  return false;
}

export async function getCurrentSession() {
  if (!hasSupabaseConfig) {
    return null;
  }

  const { data, error } = await supabase.auth.getSession();
  if (error && error.name !== 'AuthSessionMissingError') {
    throw error;
  }

  return data?.session ?? null;
}

export async function requireSession() {
  const session = await getCurrentSession();
  if (!session) {
    const redirectTo = encodeURIComponent(window.location.pathname.split('/').pop() || 'admin.html');
    window.location.replace(`login.html?redirect=${redirectTo}`);
    return null;
  }

  return session;
}

// Ett uttryckligt ?redirect= i URL:en, eller null. Tillåtna mål är befintliga
// rotfiler och Connects samtyckessida med authorization_id. Allt valideras
// som samma origin för att förhindra externa omdirigeringar.
export function getExplicitRedirect() {
  const params = new URLSearchParams(window.location.search);
  return parseSafeAuthRedirect(params.get('redirect'), window.location.origin);
}

export async function isPlatformOwner() {
  if (!hasSupabaseConfig) {
    return false;
  }

  const { data, error } = await supabase.rpc('am_i_platform_owner');
  if (error) {
    return false;
  }

  return data === true;
}

// Vart en inloggad användare hör hemma. Ett uttryckligt ?redirect= vinner,
// så djuplänkar efter utgången session leder tillbaka dit man var. Annars
// avgör rollen: analysytan är bara till för plattformsägaren, alla andra
// hör hemma på sin creator-yta.
export async function resolveHomeTarget() {
  return getExplicitRedirect() ?? ((await isPlatformOwner()) ? 'admin.html' : 'creator.html');
}
