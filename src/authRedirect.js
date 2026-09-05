const ROOT_HTML_REDIRECT = /^[a-zA-Z0-9_-]+\.html$/;

export function parseSafeAuthRedirect(rawRedirect, origin) {
  if (!rawRedirect) return null;
  if (ROOT_HTML_REDIRECT.test(rawRedirect)) return rawRedirect;

  let redirectUrl;
  try {
    redirectUrl = new URL(rawRedirect, origin);
  } catch {
    return null;
  }

  if (redirectUrl.origin !== origin) return null;
  if (!['/oauth/consent', '/oauth/consent/'].includes(redirectUrl.pathname)) return null;

  const authorizationId = redirectUrl.searchParams.get('authorization_id');
  if (!authorizationId) return null;
  if ([...redirectUrl.searchParams.keys()].some((key) => key !== 'authorization_id')) return null;

  return `/oauth/consent/?authorization_id=${encodeURIComponent(authorizationId)}`;
}
