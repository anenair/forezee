// Helpers shared by Forzee's Edge Functions.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

/// The caller's user id, read from the `sub` claim. Only safe in functions
/// with `verify_jwt = true` (config.toml): Supabase's gateway has already
/// checked the token's signature before any function code runs, so this
/// reads claims off a trusted token rather than verifying one.
export function userIdFromAuthHeader(authHeader: string | null): string | null {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const parts = authHeader.slice("Bearer ".length).split(".");
  if (parts.length !== 3) return null;

  try {
    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

/// Bypasses RLS — only for reads/writes a client must never be able to do
/// itself (another user's rows, subscription fields).
export function serviceClient(): SupabaseClient {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"));
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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
