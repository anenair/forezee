// ============================================================
// sync-subscription
// Forzee — Supabase Edge Function
//
// The only writer of profiles.subscription_tier and
// subscription_expires_at. The app used to write the tier itself,
// and since users can update their own profile row, anyone could
// set their own tier to "premium" through the public anon key —
// bypassing the free-tier limit in claude-chat and unlocking
// premium voice without paying.
//
// Now the app can only *ask* for a sync. This function asks
// RevenueCat directly, with a secret key the app never sees, and
// writes whatever RevenueCat says. The database rejects subscription
// changes from anyone but the service role (see the
// protect_subscription_columns trigger in forzee_schema.sql).
//
// Relies on RevenueCat's app user id being the Supabase user id —
// PurchaseManager.identify(userId:) calls Purchases.logIn with it.
//
// Required secret: REVENUECAT_SECRET_API_KEY — RevenueCat dashboard
// → Project → API keys → Secret key. Not the public `appl_` key the
// app uses.
// ============================================================

import { jsonResponse, requireEnv, serviceClient, userIdFromAuthHeader } from "../_shared/auth.ts";

// Matches PurchaseManager.premiumEntitlementId.
const PREMIUM_ENTITLEMENT_ID = "premium";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const userId = userIdFromAuthHeader(req.headers.get("Authorization"));
  if (!userId) {
    return jsonResponse({ error: "Missing or invalid Authorization header" }, 401);
  }

  const revenueCatResponse = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
    { headers: { "Authorization": `Bearer ${requireEnv("REVENUECAT_SECRET_API_KEY")}` } },
  );
  // On any RevenueCat failure, leave the stored tier alone — never
  // downgrade a paying user because of an outage.
  if (!revenueCatResponse.ok) {
    console.error(`RevenueCat lookup failed: ${revenueCatResponse.status}`);
    return jsonResponse({ error: "revenuecat_unavailable" }, 502);
  }

  const payload = await revenueCatResponse.json();
  const entitlement = payload?.subscriber?.entitlements?.[PREMIUM_ENTITLEMENT_ID];
  // expires_date is null for lifetime purchases.
  const expiresAt: string | null = entitlement?.expires_date ?? null;
  const isActive = entitlement !== undefined &&
    (expiresAt === null || new Date(expiresAt).getTime() > Date.now());

  const tier = isActive ? "premium" : "free";
  const { error } = await serviceClient()
    .from("profiles")
    .update({ subscription_tier: tier, subscription_expires_at: isActive ? expiresAt : null })
    .eq("id", userId);

  if (error) {
    return jsonResponse({ error: `Failed to update profile: ${error.message}` }, 500);
  }
  return jsonResponse({ tier, expires_at: isActive ? expiresAt : null });
});
