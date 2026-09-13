// ============================================================
// send-push
// Forzee — Supabase Edge Function
//
// The one place the APNs private key ever lives. Sends a push
// notification to every device registered for a given user.
//
// Auth model (no UI, this is a trusted internal primitive):
//   - Supabase's function gateway verifies the caller's JWT before
//     this code runs (default `verify_jwt = true`, see config.toml).
//   - Beyond that, this function itself only allows two callers:
//       1. The service role (role === "service_role") — a cron job
//          or another backend process, holding a secret that never
//          ships to the client. Can push to any user_id.
//       2. A user pushing to themselves (payload.user_id === the
//          caller's own sub claim) — e.g. a "send me a test
//          notification" feature. Can never target another user.
//   - Everything else is rejected with 403 before any APNs call.
//
// Device tokens are read via the service-role Supabase client,
// which bypasses RLS — that's intentional and is exactly the
// boundary RLS is meant to draw: clients can only ever touch their
// own token row (see forzee_schema.sql), only this trusted
// server-side function can read across users.
//
// Required secrets (`supabase secrets set NAME=value`):
//   APNS_KEY_ID       — Key ID for the .p8 Auth Key (Apple Developer → Keys)
//   APNS_TEAM_ID      — Your 10-character Apple Developer Team ID
//   APNS_AUTH_KEY     — The .p8 file contents, PEM format, as-is
//   APNS_BUNDLE_ID    — com.forzee.app
//   APNS_ENVIRONMENT  — "sandbox" or "production"
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically by the Supabase platform — never set those manually.
// ============================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

interface SendPushRequest {
  user_id: string;
  title: string;
  body: string;
}

interface JwtPayload {
  sub?: string;
  role?: string;
  [key: string]: unknown;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  const caller = decodeCallerFromAuthHeader(authHeader);
  if (!caller) {
    return jsonResponse({ error: "Missing or invalid Authorization header" }, 401);
  }

  let payload: SendPushRequest;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (!payload.user_id || !payload.title || !payload.body) {
    return jsonResponse({ error: "user_id, title, and body are required" }, 400);
  }

  const isServiceRole = caller.role === "service_role";
  const isSelf = caller.sub === payload.user_id;
  if (!isServiceRole && !isSelf) {
    return jsonResponse({ error: "Not authorized to push to this user" }, 403);
  }

  const supabaseUrl = requireEnv("SUPABASE_URL");
  const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { data: tokens, error: fetchError } = await supabase
    .from("device_tokens")
    .select("id, token, environment")
    .eq("user_id", payload.user_id);

  if (fetchError) {
    return jsonResponse({ error: `Failed to look up device tokens: ${fetchError.message}` }, 500);
  }
  if (!tokens || tokens.length === 0) {
    return jsonResponse({ sent: 0, message: "No registered devices for this user" }, 200);
  }

  const apnsJwt = await buildApnsJwt();
  const bundleId = requireEnv("APNS_BUNDLE_ID");

  const results = await Promise.all(
    tokens.map((row) => sendToDevice(row, apnsJwt, bundleId, payload)),
  );

  // Apple returns 400/410 for tokens that are gone for good — clean those up
  // so we stop paying the latency of pushing to a dead token every time.
  const deadTokenIds = results
    .filter((r) => r.shouldRemove)
    .map((r) => r.tokenRowId);
  if (deadTokenIds.length > 0) {
    await supabase.from("device_tokens").delete().in("id", deadTokenIds);
  }

  const sent = results.filter((r) => r.success).length;
  return jsonResponse({
    sent,
    failed: results.length - sent,
    removedInvalidTokens: deadTokenIds.length,
  });
});

// MARK: - Authorization

function decodeCallerFromAuthHeader(authHeader: string | null): JwtPayload | null {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length);
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  try {
    const json = new TextDecoder().decode(base64UrlDecode(parts[1]));
    return JSON.parse(json) as JwtPayload;
  } catch {
    return null;
  }
}

// MARK: - APNs

interface DeviceTokenRow {
  id: string;
  token: string;
  environment: string;
}

interface SendResult {
  tokenRowId: string;
  success: boolean;
  shouldRemove: boolean;
}

async function sendToDevice(
  row: DeviceTokenRow,
  apnsJwt: string,
  bundleId: string,
  payload: SendPushRequest,
): Promise<SendResult> {
  const host = row.environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";

  const response = await fetch(`${host}/3/device/${row.token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${apnsJwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify({
      aps: {
        alert: { title: payload.title, body: payload.body },
        sound: "default",
      },
    }),
  });

  if (response.ok) {
    return { tokenRowId: row.id, success: true, shouldRemove: false };
  }

  // Drain the body so the connection can be reused; we only care about status here.
  const reason = await response.text().catch(() => "");
  const isDeadToken = response.status === 400 || response.status === 410;
  console.error(`APNs send failed for token ${row.id}: ${response.status} ${reason}`);

  return { tokenRowId: row.id, success: false, shouldRemove: isDeadToken };
}

/// Builds a fresh ES256 provider authentication JWT for every invocation.
/// Apple allows reusing one for up to an hour; regenerating each call trades
/// a little latency for a much simpler, stateless function.
async function buildApnsJwt(): Promise<string> {
  const keyId = requireEnv("APNS_KEY_ID");
  const teamId = requireEnv("APNS_TEAM_ID");
  const privateKeyPem = requireEnv("APNS_AUTH_KEY");

  const header = { alg: "ES256", kid: keyId };
  const claims = { iss: teamId, iat: Math.floor(Date.now() / 1000) };

  const encodedHeader = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
  const encodedClaims = base64UrlEncode(new TextEncoder().encode(JSON.stringify(claims)));
  const signingInput = `${encodedHeader}.${encodedClaims}`;

  const privateKey = await importApnsPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

async function importApnsPrivateKey(pem: string): Promise<CryptoKey> {
  const der = pemToDer(pem);
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

// MARK: - Helpers

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(
    value.length + (4 - (value.length % 4)) % 4,
    "=",
  );
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
