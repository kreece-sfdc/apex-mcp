#!/usr/bin/env node
/**
 * PCMetrics MCP stdio proxy
 *
 * Translates Claude Code's stdio JSON-RPC transport to HTTP POSTs against
 * the Salesforce Apex REST endpoint. Handles OAuth2 auth-code + PKCE on first
 * run, stores refresh token locally, and silently refreshes access tokens.
 *
 * Environment variables (all optional — defaults work for apex-mcp-scratch):
 *   SFDC_INSTANCE_URL   Org instance URL  (default: read from token store or sf org display)
 *   SFDC_TARGET_ORG     sf CLI org alias  (default: apex-mcp-scratch)
 *   SFDC_MCP_PATH       Apex REST path    (default: /services/apexrest/pcmetrics/mcp/)
 *   SFDC_CLIENT_ID      ECA consumer key  (required for OAuth2 PKCE flow)
 *   SFDC_TOKEN_FILE     Token store path  (default: ~/.sfdc-pcmetrics-tokens.json)
 *   SFDC_AUTH_PORT      Local callback port (default: 7717)
 */

'use strict';

const https = require('https');
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ── Config ────────────────────────────────────────────────────────────────────

const TARGET_ORG   = process.env.SFDC_TARGET_ORG   || 'apex-mcp-scratch';
const MCP_PATH     = process.env.SFDC_MCP_PATH      || '/services/apexrest/pcmetrics/mcp/';
const CLIENT_ID    = process.env.SFDC_CLIENT_ID     || null;
const TOKEN_FILE   = process.env.SFDC_TOKEN_FILE    ||
                     path.join(process.env.HOME || process.env.USERPROFILE, '.sfdc-pcmetrics-tokens.json');

let INSTANCE_URL = process.env.SFDC_INSTANCE_URL || null;

// ── Token store ───────────────────────────────────────────────────────────────

function loadTokens() {
  try { return JSON.parse(fs.readFileSync(TOKEN_FILE, 'utf8')); } catch { return {}; }
}

function saveTokens(data) {
  fs.writeFileSync(TOKEN_FILE, JSON.stringify(data, null, 2), { mode: 0o600 });
}

// ── PKCE helpers ──────────────────────────────────────────────────────────────

function generateCodeVerifier() {
  return crypto.randomBytes(32).toString('base64url');
}

function generateCodeChallenge(verifier) {
  return crypto.createHash('sha256').update(verifier).digest('base64url');
}

// ── HTTP helper ───────────────────────────────────────────────────────────────

function postForm(url, params) {
  return new Promise((resolve, reject) => {
    const body = new URLSearchParams(params).toString();
    const parsed = new URL(url);
    const mod = parsed.protocol === 'https:' ? https : http;
    const req = mod.request({
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch { reject(new Error(`Non-JSON response: ${data}`)); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function postJson(url, bodyObj, headers) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(bodyObj);
    const parsed = new URL(url);
    const mod = parsed.protocol === 'https:' ? https : http;
    const req = mod.request({
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
        'Accept': 'application/json, text/event-stream',
        'MCP-Protocol-Version': '2025-11-25',
        ...headers,
      },
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ── OAuth2 PKCE auth-code flow ─────────────────────────────────────────────────

const AUTH_PORT = parseInt(process.env.SFDC_AUTH_PORT || '7717', 10);

function runPKCEFlow(instanceUrl) {
  return new Promise((resolve, reject) => {
    const verifier = generateCodeVerifier();
    const challenge = generateCodeChallenge(verifier);
    const redirectUri = `http://localhost:${AUTH_PORT}/oauth/callback`;

    const authUrl = `${instanceUrl}/services/oauth2/authorize?` + new URLSearchParams({
      response_type: 'code',
      client_id: CLIENT_ID,
      redirect_uri: redirectUri,
      code_challenge: challenge,
      code_challenge_method: 'S256',
      scope: 'api refresh_token',
    });

    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, `http://localhost:${AUTH_PORT}`);
      if (!url.pathname.startsWith('/oauth/callback')) {
        res.writeHead(404); res.end(); return;
      }
      const code = url.searchParams.get('code');
      const error = url.searchParams.get('error');

      if (error) {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end('<h2>Authorization failed</h2><p>' + error + '</p>');
        server.close();
        return reject(new Error(`OAuth error: ${error} — ${url.searchParams.get('error_description') || ''}`));
      }

      if (!code) {
        res.writeHead(400, { 'Content-Type': 'text/html' });
        res.end('<h2>Missing code</h2>');
        server.close();
        return reject(new Error('OAuth callback missing code parameter'));
      }

      try {
        const result = await postForm(`${instanceUrl}/services/oauth2/token`, {
          grant_type: 'authorization_code',
          code,
          redirect_uri: redirectUri,
          client_id: CLIENT_ID,
          code_verifier: verifier,
        });

        if (result.error) throw new Error(`${result.error}: ${result.error_description}`);

        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end('<h2>Authorization successful!</h2><p>You can close this tab and return to Claude Code.</p>');
        server.close();
        resolve(result);
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'text/html' });
        res.end('<h2>Token exchange failed</h2><p>' + err.message + '</p>');
        server.close();
        reject(err);
      }
    });

    server.listen(AUTH_PORT, 'localhost', () => {
      process.stderr.write(
        `\n[pcmetrics-mcp] No refresh token found. Open this URL to authorize:\n\n` +
        `  ${authUrl}\n\n` +
        `Waiting for OAuth callback on port ${AUTH_PORT}...\n\n`
      );
    });

    server.on('error', reject);
  });
}

// ── Token refresh ─────────────────────────────────────────────────────────────

async function refreshWithToken(instanceUrl, refreshToken) {
  const params = {
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: CLIENT_ID,
  };
  const result = await postForm(`${instanceUrl}/services/oauth2/token`, params);
  if (result.error) throw new Error(`${result.error}: ${result.error_description}`);
  return result;
}

// ── sf CLI fallback ───────────────────────────────────────────────────────────

function getTokenViaCLI() {
  try {
    const out = execSync(`sf org display --target-org ${TARGET_ORG} --json 2>/dev/null`, { encoding: 'utf8' });
    const data = JSON.parse(out).result;
    const token = data.accessToken;
    // Newer sf CLI redacts the token — can't use it
    if (!token || token.startsWith('[REDACTED]')) {
      throw new Error(`sf CLI redacts access tokens — run 'node ${__filename} auth' to authorize via OAuth2`);
    }
    return { access_token: token, instance_url: data.instanceUrl };
  } catch (err) {
    throw new Error(`sf org display failed: ${err.message}`);
  }
}

// ── Access token management ───────────────────────────────────────────────────

let tokenCache = null; // { accessToken, expiresAt }
let refreshInFlight = null;

async function getAccessToken() {
  // Return cached if still valid (with 60s buffer)
  if (tokenCache && tokenCache.expiresAt > Date.now() + 60_000) {
    return { accessToken: tokenCache.accessToken, instanceUrl: INSTANCE_URL };
  }

  // If a refresh is already running, wait for it
  if (refreshInFlight) return refreshInFlight;

  refreshInFlight = (async () => {
    try {
      const tokens = loadTokens();

      if (!CLIENT_ID) {
        // No ECA configured — fall back to sf CLI session token
        const { access_token, instance_url } = getTokenViaCLI();
        if (!INSTANCE_URL) INSTANCE_URL = instance_url;
        tokenCache = { accessToken: access_token, expiresAt: Date.now() + 7_200_000 };
        return { accessToken: access_token, instanceUrl: INSTANCE_URL };
      }

      if (!INSTANCE_URL && tokens.instance_url) INSTANCE_URL = tokens.instance_url;
      if (!INSTANCE_URL) {
        const { instance_url } = getTokenViaCLI();
        INSTANCE_URL = instance_url;
      }

      if (tokens.refresh_token) {
        // Refresh existing token
        const result = await refreshWithToken(INSTANCE_URL, tokens.refresh_token);
        const updated = {
          ...tokens,
          access_token: result.access_token,
          instance_url: result.instance_url || INSTANCE_URL,
        };
        // If rotation returned a new refresh token, persist it
        if (result.refresh_token) updated.refresh_token = result.refresh_token;
        saveTokens(updated);
        INSTANCE_URL = updated.instance_url;
        tokenCache = { accessToken: result.access_token, expiresAt: Date.now() + (result.expires_in || 7200) * 1000 };
        return { accessToken: result.access_token, instanceUrl: INSTANCE_URL };
      }

      // No refresh token — fail fast; user must run 'node mcp-proxy.js auth' first
      throw new Error(
        `No refresh token found. Run: node ${__filename} auth\n` +
        `This opens a browser to authorize the MCP proxy and saves a refresh token to ${TOKEN_FILE}.`
      );
    } finally {
      refreshInFlight = null;
    }
  })();

  return refreshInFlight;
}

// ── MCP request forwarding ────────────────────────────────────────────────────

async function forwardRequest(msg) {
  const isNotification = msg.id === undefined || msg.id === null;
  let { accessToken, instanceUrl } = await getAccessToken();

  const url = instanceUrl.replace(/\/$/, '') + MCP_PATH;
  let result = await postJson(url, msg, { Authorization: `Bearer ${accessToken}` });

  if (result.status === 401) {
    // Force token refresh and retry once
    tokenCache = null;
    ({ accessToken, instanceUrl } = await getAccessToken());
    result = await postJson(url, msg, { Authorization: `Bearer ${accessToken}` });
  }

  if (result.status === 400) {
    throw new Error(`HTTP 400 at ${url}`);
  }

  // Notifications return 202 with empty body — nothing to write to stdout
  if (isNotification || result.status === 202 || !result.body.trim()) return null;

  return result.body;
}

// ── stdio transport ───────────────────────────────────────────────────────────

let buffer = '';

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buffer += chunk;
  const lines = buffer.split('\n');
  buffer = lines.pop(); // Keep incomplete last line
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    handleLine(trimmed);
  }
});

process.stdin.on('end', () => process.exit(0));

// ── 'auth' subcommand — run PKCE flow once to get & store refresh token ───────

async function runAuth() {
  if (!CLIENT_ID) {
    console.error('SFDC_CLIENT_ID is not set. Export it before running auth.');
    process.exit(1);
  }
  const instanceUrl = INSTANCE_URL || (() => {
    try {
      const out = execSync(`sf org display --target-org ${TARGET_ORG} --json 2>/dev/null`, { encoding: 'utf8' });
      return JSON.parse(out).result.instanceUrl;
    } catch { return null; }
  })();
  if (!instanceUrl) {
    console.error('Could not determine instance URL. Set SFDC_INSTANCE_URL or ensure sf org is authenticated.');
    process.exit(1);
  }
  INSTANCE_URL = instanceUrl;
  console.log(`Authorizing against ${instanceUrl}...`);
  try {
    const result = await runPKCEFlow(instanceUrl);
    saveTokens({
      access_token:  result.access_token,
      refresh_token: result.refresh_token,
      instance_url:  result.instance_url || instanceUrl,
      issued_at:     Date.now(),
    });
    console.log(`\nAuthorization successful. Refresh token saved to ${TOKEN_FILE}`);
    console.log('You can now reconnect the MCP server with: /mcp reconnect pcmetrics');
    process.exit(0);
  } catch (err) {
    console.error(`Authorization failed: ${err.message}`);
    process.exit(1);
  }
}

// ── Entrypoint ────────────────────────────────────────────────────────────────

if (process.argv[2] === 'auth') { runAuth(); }

async function handleLine(line) {
  let msg;
  try { msg = JSON.parse(line); }
  catch { return; } // Ignore unparseable input

  try {
    const response = await forwardRequest(msg);
    if (response) process.stdout.write(response + '\n');
  } catch (err) {
    const isNotification = msg.id === undefined || msg.id === null;
    if (!isNotification) {
      process.stdout.write(JSON.stringify({
        jsonrpc: '2.0',
        id: msg.id,
        error: { code: -32603, message: err.message },
      }) + '\n');
    }
    process.stderr.write(`[pcmetrics-mcp] Error: ${err.message}\n`);
  }
}
