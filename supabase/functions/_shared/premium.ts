import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/// Premium only while the stored expiry is in the future (null = lifetime).
/// Trustworthy because clients can't write these columns: the
/// protect_subscription_columns trigger (forzee_schema.sql) rejects any
/// change that doesn't come from the service role, and only
/// sync-subscription writes them, straight from RevenueCat.
export async function isPremium(supabase: SupabaseClient, userId: string): Promise<boolean> {
  const { data } = await supabase
    .from("profiles")
    .select("subscription_tier, subscription_expires_at")
    .eq("id", userId)
    .single();

  if (data?.subscription_tier !== "premium") return false;
  if (!data.subscription_expires_at) return true;
  return new Date(data.subscription_expires_at).getTime() > Date.now();
}
