-- ============================================================
-- One-time patch for a Forzee database created from an older
-- forzee_schema.sql. Paste into Supabase Dashboard → SQL Editor
-- and run once. Safe to re-run. New projects get this from
-- forzee_schema.sql directly and don't need it.
-- ============================================================

-- 1. daily_usage_summary respected nobody's RLS: any signed-in user
--    could read every user's usage and cost through the anon key.
alter view public.daily_usage_summary set (security_invoker = true);

-- 2. Users could set their own profiles.subscription_tier to
--    'premium'. Subscription fields now only change via the
--    service role (the sync-subscription Edge Function).
create or replace function public.protect_subscription_columns()
returns trigger
language plpgsql
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.subscription_tier := 'free';
    new.subscription_expires_at := null;
  elsif new.subscription_tier is distinct from old.subscription_tier
     or new.subscription_expires_at is distinct from old.subscription_expires_at then
    raise exception 'subscription fields can only be changed server-side'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_subscription_columns on public.profiles;
create trigger protect_subscription_columns
  before insert or update on public.profiles
  for each row execute function public.protect_subscription_columns();

-- 3. Existing premium rows can't be trusted: the app wrote the tier
--    itself and never an expiry, so a self-granted premium would look
--    like a lifetime subscription. Reset everyone to free; real
--    subscribers are restored from RevenueCat by sync-subscription the
--    next time they open the app.
update public.profiles
set subscription_tier = 'free', subscription_expires_at = null
where subscription_tier is distinct from 'free';
