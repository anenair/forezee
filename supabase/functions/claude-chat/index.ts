// ============================================================
// claude-chat
// Forzee — Supabase Edge Function
//
// The one place the Anthropic API key ever lives. Every Claude
// call ClaudeAPIClient.swift makes goes through here now, instead
// of straight to api.anthropic.com with a key shipped inside the
// app bundle — that key was extractable from the IPA by anyone
// (strings on the binary, or just reading Info.plist), with no
// per-user attribution and nothing stopping them calling Claude
// directly with it, unlimited, billed to Forzee's own account.
//
// This function does two things a client-held key never could:
//   1. Keeps ANTHROPIC_API_KEY server-side, never sent to any device.
//   2. Re-enforces UsageGate's free-tier daily limit here, derived
//      from the caller's own verified session — not from whatever
//      user_id or tier a client claims. A patched or jailbroken
//      client can lie to itself; it can't lie to this function,
//      because the limit check reads from `sub` on a JWT Supabase's
//      own gateway already verified (see config.toml — verify_jwt
//      = true rejects anything invalid before this code even runs).
//
// The request body is passed straight through from the client (see
// ClaudeAPIClient.swift's *jsonValue helpers — model/system/messages/
// tools/tool_choice/stream, already shaped exactly as Anthropic wants
// them, cache_control markers included) with one addition: a
// `task_type` field this function reads for the limit check and
// strips before forwarding. That keeps this function a thin proxy,
// not a second place request-shaping logic has to be kept in sync.
//
// Required secret (`supabase secrets set ANTHROPIC_API_KEY=sk-ant-...`):
//   ANTHROPIC_API_KEY — the real Claude API key, from console.anthropic.com
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically by the Supabase platform — never set those manually.
// ============================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Mirrors UsageGate.swift's freeTierDailyLimits exactly — keep these two
// in sync by hand; there's no shared source of truth between Swift and
// Deno. Anything not listed here passes through unlimited, same as
// UsageGate's own `freeTierDailyLimits[taskType] ?? .max` default.
const FREE_TIER_DAILY_LIMITS: Record<string, number> = {
  "chat_message": 3,
  "workout_generation": 1,
};

interface JwtPayload {
  sub?: string;
  [key: string]: unknown;
}

interface DailyUsageSummaryRow {
  chat_messages_today: number;
  workouts_generated_today: number;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  const userId = decodeUserId(authHeader);
  if (!userId) {
    return jsonResponse({ error: "Missing or invalid Authorization header" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const taskType = typeof body.task_type === "string" ? body.task_type : "unspecified";
  delete body.task_type; // Anthropic doesn't know this field — never forward it.

  const supabaseUrl = requireEnv("SUPABASE_URL");
  const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const limitError = await checkFreeTierLimit(supabase, userId, taskType);
  if (limitError) {
    return jsonResponse(limitError, 429);
  }

  const anthropicApiKey = requireEnv("ANTHROPIC_API_KEY");
  const anthropicResponse = await fetch(ANTHROPIC_MESSAGES_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": anthropicApiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify(body),
  });

  // Streamed straight through, not buffered — anthropicResponse.body is a
  // ReadableStream, and returning it as-is here keeps token-by-token SSE
  // delivery intact all the way to ClaudeAPIClient's urlSession.bytes(for:)
  // on the other end. Buffering it first (e.g. via .text()) would turn
  // every streamed reply into one long pause followed by the whole thing
  // at once.
  return new Response(anthropicResponse.body, {
    status: anthropicResponse.status,
    headers: {
      "content-type": anthropicResponse.headers.get("content-type") ?? "application/json",
    },
  });
});

// MARK: - Free-tier enforcement

async function checkFreeTierLimit(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  taskType: string,
): Promise<{ error: string; task_type: string; limit: number; used: number } | null> {
  const limit = FREE_TIER_DAILY_LIMITS[taskType];
  if (limit === undefined) return null; // Not a limited task type — same as UsageGate's .max default.

  const { data: profile } = await supabase
    .from("profiles")
    .select("subscription_tier")
    .eq("id", userId)
    .single();

  if (profile?.subscription_tier && profile.subscription_tier !== "free") {
    return null; // Premium — unconditional pass, same as UsageGate.checkLimit.
  }

  const { data: summary } = await supabase
    .from("daily_usage_summary")
    .select("chat_messages_today, workouts_generated_today")
    .eq("user_id", userId)
    .maybeSingle() as { data: DailyUsageSummaryRow | null };

  const used = taskType === "chat_message"
    ? (summary?.chat_messages_today ?? 0)
    : (summary?.workouts_generated_today ?? 0);

  if (used >= limit) {
    return { error: "limit_reached", task_type: taskType, limit, used };
  }
  return null;
}

// MARK: - Auth

/// The JWT's signature was already verified by Supabase's function gateway
/// (verify_jwt = true in config.toml) before this code ever runs — this
/// just reads the `sub` claim off an already-trusted token, the same
/// reasoning send-push's decodeCallerFromAuthHeader uses.
function decodeUserId(authHeader: string | null): string | null {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length);
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  try {
    const json = new TextDecoder().decode(base64UrlDecode(parts[1]));
    const payload = JSON.parse(json) as JwtPayload;
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

// MARK: - Helpers

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
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
