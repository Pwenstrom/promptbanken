import { hasSupabaseConfig, supabase } from './supabaseClient.js';

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

// Ett uttryckligt ?redirect= i URL:en, eller null. Mönstret släpper bara
// igenom ett filnamn i roten — ingen sökväg, inget schema, ingen värd — så
// en länk utifrån kan inte skicka en inloggad användare vidare någon
// annanstans.
export function getExplicitRedirect() {
  const params = new URLSearchParams(window.location.search);
  const redirect = params.get('redirect');
  if (!redirect || !/^[a-zA-Z0-9_-]+\.html$/.test(redirect)) {
    return null;
  }

  return redirect;
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
