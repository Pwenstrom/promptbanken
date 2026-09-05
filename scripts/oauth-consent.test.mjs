import assert from 'node:assert/strict';
import test from 'node:test';

import { parseSafeAuthRedirect } from '../src/authRedirect.js';
import {
  buildConsentLoginUrl,
  decideAuthorization,
  loadAuthorizationRequest
} from '../src/oauthConsentFlow.js';


test('samtyckesreturen tillåts inom appen och bevarar authorization_id', () => {
  const redirect = parseSafeAuthRedirect(
    '/oauth/consent/?authorization_id=request-123',
    'https://app.promptbanken.se'
  );

  assert.equal(redirect, '/oauth/consent/?authorization_id=request-123');
});


test('extern eller manipulerad login-retur avvisas', () => {
  assert.equal(
    parseSafeAuthRedirect('https://evil.example/oauth/consent/?authorization_id=x', 'https://app.promptbanken.se'),
    null
  );
  assert.equal(
    parseSafeAuthRedirect('/oauth/consent/?authorization_id=x&next=https://evil.example', 'https://app.promptbanken.se'),
    null
  );
});


test('loginlänken bevarar hela samtyckesförfrågan', () => {
  assert.equal(
    buildConsentLoginUrl('request 123', 'https://app.promptbanken.se'),
    'https://app.promptbanken.se/login.html?redirect=%2Foauth%2Fconsent%2F%3Fauthorization_id%3Drequest%2520123'
  );
});


test('en ny förfrågan returnerar klient och begärda scopes', async () => {
  const oauth = {
    getAuthorizationDetails: async () => ({
      data: {
        authorization_id: 'request-123',
        client: { name: 'ChatGPT' },
        scope: 'openid email profile'
      },
      error: null
    })
  };

  assert.deepEqual(await loadAuthorizationRequest(oauth, 'request-123'), {
    kind: 'consent',
    authorizationId: 'request-123',
    clientName: 'ChatGPT',
    scopes: ['openid', 'email', 'profile']
  });
});


test('tidigare samtycke returnerar direkt klientens säkra retur-URL', async () => {
  const oauth = {
    getAuthorizationDetails: async () => ({
      data: { redirect_url: 'https://chatgpt.com/oauth/callback?code=abc' },
      error: null
    })
  };

  assert.deepEqual(await loadAuthorizationRequest(oauth, 'request-123'), {
    kind: 'redirect',
    redirectUrl: 'https://chatgpt.com/oauth/callback?code=abc'
  });
});


test('godkänn och neka använder Supabases beslut och retur-URL', async () => {
  const calls = [];
  const oauth = {
    approveAuthorization: async (id) => {
      calls.push(['approve', id]);
      return { data: { redirect_url: 'https://client.example/approved' }, error: null };
    },
    denyAuthorization: async (id) => {
      calls.push(['deny', id]);
      return { data: { redirect_url: 'https://client.example/denied' }, error: null };
    }
  };

  assert.equal(await decideAuthorization(oauth, 'request-123', 'approve'), 'https://client.example/approved');
  assert.equal(await decideAuthorization(oauth, 'request-123', 'deny'), 'https://client.example/denied');
  assert.deepEqual(calls, [['approve', 'request-123'], ['deny', 'request-123']]);
});
