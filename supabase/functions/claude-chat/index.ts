// ============================================================
// claude-chat
// Forzee — Supabase Edge Function
//
// The one place the Anthropic API key ever lives. Every Claude
// call ClaudeAPIClient.swift makes goes through here instead of
// straight to api.anthropic.com with a key shipped inside the app
// bundle, where anyone could extract it and call Claude unlimited
// on Forzee's account.
//
// On every request:
//   1. Supabase's gateway rejects callers without a valid session
//      (verify_jwt = true in config.toml) before this code runs.
//   2. The free-tier daily limit is re-checked here, keyed on the
//      verified JWT's user id — not on anything the client claims.
//   3. The request body is forwarded to Anthropic unchanged and the
//      response streamed straight back.
//
// The body is exactly what ClaudeAPIClient.swift builds (model/
// system/messages/tools/tool_choice/stream, cache_control markers
// included) plus one `task_type` field this function reads for the
// limit check and strips before forwarding.
//
// Required secret: ANTHROPIC_API_KEY
// (`supabase secrets set ANTHROPIC_API_KEY=sk-ant-...`).
// ============================================================

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { jsonResponse, requireEnv, serviceClient, userIdFromAuthHeader } from "../_shared/auth.ts";
import { isPremium } from "../_shared/premium.ts";

const ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Mirrors UsageGate.swift's freeTierDailyLimits exactly — there's no shared
// source of truth between Swift and Deno, so keep the two in sync by hand.
// Anything not listed passes through unlimited, same as UsageGate's `.max`.
const FREE_TIER_DAILY_LIMITS: Record<string, number> = {
  "chat_message": 3,
  "workout_generation": 1,
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const userId = userIdFromAuthHeader(req.headers.get("Authorization"));
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

  const limitError = await checkFreeTierLimit(serviceClient(), userId, taskType);
  if (limitError) {
    return jsonResponse(limitError, 429);
  }

  const anthropicResponse = await fetch(ANTHROPIC_MESSAGES_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": requireEnv("ANTHROPIC_API_KEY"),
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify(body),
  });

  // Returned as a stream, not buffered — buffering (e.g. via .text()) would
  // turn every token-by-token reply into one long pause.
  return new Response(anthropicResponse.body, {
    status: anthropicResponse.status,
    headers: {
      "content-type": anthropicResponse.headers.get("content-type") ?? "application/json",
    },
  });
});

async function checkFreeTierLimit(
  supabase: SupabaseClient,
  userId: string,
  taskType: string,
): Promise<{ error: string; task_type: string; limit: number; used: number } | null> {
  const limit = FREE_TIER_DAILY_LIMITS[taskType];
  if (limit === undefined) return null;
  if (await isPremium(supabase, userId)) return null;

  const { data: summary } = await supabase
    .from("daily_usage_summary")
    .select("chat_messages_today, workouts_generated_today")
    .eq("user_id", userId)
    .maybeSingle();

  const used = taskType === "chat_message"
    ? (summary?.chat_messages_today ?? 0)
    : (summary?.workouts_generated_today ?? 0);

  return used >= limit ? { error: "limit_reached", task_type: taskType, limit, used } : null;
}
