// ============================================================
// kai-voice
// Forzee — Supabase Edge Function
//
// The one place the ElevenLabs API key lives. Turns Kai's reply
// text into audio in Kai's custom voice for premium users. The
// key used to ship inside the app bundle, where anyone could
// extract it and generate unlimited speech on Forzee's account.
//
// On every request:
//   1. Supabase's gateway rejects callers without a valid session
//      (verify_jwt = true in config.toml).
//   2. The caller must be premium, checked server-side (see
//      _shared/premium.ts) — the custom voice is a paid feature.
//   3. Text length is capped, since ElevenLabs bills per character.
//
// Returns audio/mpeg on success. Any failure is a JSON error the
// app treats as "fall back to the free system voice".
//
// Required secrets:
//   ELEVENLABS_API_KEY  — from elevenlabs.io → Profile → API Keys
//   ELEVENLABS_VOICE_ID — Kai's voice id
// ============================================================

import { jsonResponse, requireEnv, serviceClient, userIdFromAuthHeader } from "../_shared/auth.ts";
import { isPremium } from "../_shared/premium.ts";

const ELEVENLABS_MODEL = "eleven_turbo_v2_5";
// Longer than any single Kai reply; bounds what one request can cost.
const MAX_TEXT_CHARS = 2_000;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const userId = userIdFromAuthHeader(req.headers.get("Authorization"));
  if (!userId) {
    return jsonResponse({ error: "Missing or invalid Authorization header" }, 401);
  }

  let text: unknown;
  try {
    ({ text } = await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  if (typeof text !== "string" || text.trim().length === 0) {
    return jsonResponse({ error: "text is required" }, 400);
  }
  if (text.length > MAX_TEXT_CHARS) {
    return jsonResponse({ error: "text_too_long", max: MAX_TEXT_CHARS }, 413);
  }

  if (!(await isPremium(serviceClient(), userId))) {
    return jsonResponse({ error: "premium_required" }, 403);
  }

  const voiceId = requireEnv("ELEVENLABS_VOICE_ID");
  const elevenLabsResponse = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: "POST",
    headers: {
      "xi-api-key": requireEnv("ELEVENLABS_API_KEY"),
      "content-type": "application/json",
      "accept": "audio/mpeg",
    },
    body: JSON.stringify({ text, model_id: ELEVENLABS_MODEL }),
  });

  if (!elevenLabsResponse.ok) {
    const reason = await elevenLabsResponse.text().catch(() => "");
    console.error(`ElevenLabs failed: ${elevenLabsResponse.status} ${reason}`);
    return jsonResponse({ error: "voice_unavailable" }, 502);
  }

  return new Response(elevenLabsResponse.body, {
    status: 200,
    headers: { "content-type": "audio/mpeg" },
  });
});
