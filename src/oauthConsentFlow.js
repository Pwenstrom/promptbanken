export function buildConsentLoginUrl(authorizationId, origin) {
  const consentPath = `/oauth/consent/?authorization_id=${encodeURIComponent(authorizationId)}`;
  const loginUrl = new URL('/login.html', origin);
  loginUrl.searchParams.set('redirect', consentPath);
  return loginUrl.toString();
}

export async function loadAuthorizationRequest(oauth, authorizationId) {
  if (!authorizationId) {
    throw new Error('OAuth-förfrågan saknar authorization_id.');
  }

  const { data, error } = await oauth.getAuthorizationDetails(authorizationId);
  if (error) throw error;
  if (!data) throw new Error('OAuth-förfrågan kunde inte läsas.');

  if (!('authorization_id' in data)) {
    if (!data.redirect_url) throw new Error('OAuth-förfrågan saknar returadress.');
    return { kind: 'redirect', redirectUrl: data.redirect_url };
  }

  const scopes = String(data.scope || '')
    .split(/\s+/)
    .filter(Boolean);

  return {
    kind: 'consent',
    authorizationId: data.authorization_id,
    clientName: data.client?.name || 'En extern AI-tjänst',
    scopes
  };
}

export async function decideAuthorization(oauth, authorizationId, decision) {
  const method = decision === 'approve'
    ? oauth.approveAuthorization.bind(oauth)
    : decision === 'deny'
      ? oauth.denyAuthorization.bind(oauth)
      : null;

  if (!method) throw new Error('Okänt OAuth-beslut.');

  const { data, error } = await method(authorizationId);
  if (error) throw error;
  if (!data?.redirect_url) throw new Error('OAuth-svaret saknar returadress.');
  return data.redirect_url;
}
