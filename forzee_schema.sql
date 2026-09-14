-- ============================================================
-- Forzee — Supabase Schema v1.0
-- Covers Phase 1 fully, extensible for Phase 2 & 3
-- Run this in Supabase SQL Editor
-- ============================================================

-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- ============================================================
-- USERS
-- Extended profile on top of Supabase auth.users
-- ============================================================
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),

  -- Identity
  full_name text,
  avatar_url text,

  -- Fitness level (drives AI coaching tone & complexity)
  -- novice | returning | intermediate | advanced
  fitness_level text not null default 'novice',

  -- Goals (array — user can have multiple)
  -- e.g. ["lose_weight", "build_muscle", "improve_endurance"]
  goals text[] default '{}',

  -- Equipment available
  -- e.g. ["bodyweight", "dumbbells", "barbell", "cables", "full_gym"]
  equipment text[] default '{"bodyweight"}',

  -- Preferred workout days e.g. ["monday", "wednesday", "friday"]
  preferred_days text[] default '{}',

  -- How much Kai initiates contact vs. waits to be asked
  -- advisory | guided | accountability
  coach_mode text not null default 'guided',

  -- Preferred session duration in minutes
  preferred_duration_mins int default 45,

  -- Injuries or limitations (free text for AI context)
  limitations text,

  -- Training preferences (roadmap Phase 4 "My Plan") — onboarding never
  -- collects these, they only exist because the My Plan settings screen
  -- does. `not null default` so an existing row picks up a sane value the
  -- moment this migration runs, same as every other preference here.
  -- full_body | upper_lower | push_pull_legs | body_part_split | let_kai_decide
  training_split text not null default 'let_kai_decide',
  -- low | moderate | high
  exercise_variability text not null default 'moderate',
  warmup_sets_enabled boolean not null default true,
  circuits_supersets_enabled boolean not null default false,
  -- lbs | kg — display/phrasing preference only, storage is always kg
  weight_unit text not null default 'lbs',
  -- monday | sunday
  start_of_week text not null default 'monday',

  -- Personal profile ("About You" settings screen — separate from
  -- onboarding, separate from My Plan's training preferences above).
  -- All nullable, no defaults: unlike the training preferences above,
  -- there's no sane universal default for someone's birth date or weight.
  -- date_of_birth is timestamptz (not a plain `date`) purely so it decodes
  -- through the same .iso8601 JSONDecoder strategy every other timestamp
  -- on this table already uses in ForzeeDataService.fetchProfile — a plain
  -- `date` column round-trips as "1990-05-14" with no time component, which
  -- that decoder rejects outright.
  date_of_birth timestamp with time zone,
  -- male | female | unspecified — asked only for BMR/calorie-estimate
  -- formulas, which differ by biological sex.
  biological_sex text,
  height_cm numeric,
  current_weight_kg numeric,
  target_weight_kg numeric,
  body_fat_percent numeric,
  waist_cm numeric,
  hip_cm numeric,
  -- under_1 | one_to_three | three_to_five | five_plus
  years_training_bucket text,
  training_background_notes text,
  motivation_notes text,

  -- Onboarding complete flag
  onboarding_complete boolean default false,

  -- Subscription tier: free | premium
  subscription_tier text default 'free',
  subscription_expires_at timestamp with time zone
);

-- ============================================================
-- EXERCISES
-- Master exercise database
-- ============================================================
create table public.exercises (
  id uuid default uuid_generate_v4() primary key,
  created_at timestamp with time zone default now(),

  name text not null,
  slug text unique not null, -- e.g. "barbell-back-squat"
  description text,

  -- Categorization
  muscle_groups text[] default '{}',   -- ["quads", "glutes", "hamstrings"]
  equipment_needed text[] default '{}', -- ["barbell", "rack"]
  difficulty text default 'beginner',   -- beginner | intermediate | advanced
  category text,                         -- strength | cardio | mobility | plyometric

  -- Media
  video_url text,
  thumbnail_url text,

  -- Form cues (used by AI for novice guidance)
  form_cues text[] default '{}',

  -- Metadata
  is_active boolean default true
);

-- ============================================================
-- WORKOUT PLANS
-- AI-generated or template plans assigned to a user
-- ============================================================
create table public.workout_plans (
  id uuid default uuid_generate_v4() primary key,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,

  name text not null,
  description text,

  -- Plan metadata
  duration_weeks int,          -- e.g. 8-week program
  days_per_week int,
  difficulty text,

  -- Source: ai_generated | template | custom
  source text default 'ai_generated',

  -- Full plan structure stored as JSON for flexibility
  plan_data jsonb default '{}',

  is_active boolean default true
);

-- ============================================================
-- WORKOUTS
-- Individual scheduled or ad-hoc workouts
-- ============================================================
create table public.workouts (
  id uuid default uuid_generate_v4() primary key,
  created_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,
  plan_id uuid references public.workout_plans(id) on delete set null,

  name text not null,
  scheduled_at timestamp with time zone,

  -- Workout type: strength | cardio | mobility | hiit | recovery
  workout_type text default 'strength',

  -- Estimated duration in minutes
  estimated_duration_mins int,

  -- AI context snapshot used to generate this workout
  -- Stores sleep score, HRV, calendar busyness etc at time of generation
  context_snapshot jsonb default '{}',

  -- Status: scheduled | completed | skipped
  status text default 'scheduled',

  -- Exercises in this workout (ordered)
  exercises jsonb default '[]',
  -- Structure: [{ exercise_id, sets, reps, weight_kg, rest_secs, notes }]

  -- Exactly when Kai produced this plan — distinct from created_at (when
  -- this row was first saved), which can trail generation by however long
  -- the user sat on the workout before starting. "Times used" for a given
  -- workout is a COUNT of sessions.workout_id, not a column here — see
  -- ForzeeDataService.saveCompletedWorkout's isRepeat parameter, which
  -- skips inserting a new workouts row entirely when repeating one.
  generated_at timestamp with time zone default now()
);

-- ============================================================
-- SESSIONS
-- Actual completed workout sessions (user's performance log)
-- ============================================================
create table public.sessions (
  id uuid default uuid_generate_v4() primary key,
  started_at timestamp with time zone default now(),
  completed_at timestamp with time zone,

  user_id uuid references public.profiles(id) on delete cascade,
  workout_id uuid references public.workouts(id) on delete set null,

  -- Actual duration
  duration_mins int,

  -- Performance log
  sets_log jsonb default '[]',
  -- Structure: [{ exercise_id, set_number, reps_completed, weight_kg, rpe }]

  -- User feedback post-session
  perceived_effort int check (perceived_effort between 1 and 10),
  mood_post text,  -- great | good | okay | tired | rough
  notes text,

  -- Overall session rating 1-5
  rating int check (rating between 1 and 5)
);

-- ============================================================
-- CONTEXT SIGNALS
-- Phase 2: Health & life signals that feed the AI coach
-- Schema ready now, populated in Phase 2
-- ============================================================
create table public.context_signals (
  id uuid default uuid_generate_v4() primary key,
  recorded_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,

  -- Signal type: sleep | hrv | steps | stress | calendar_busyness | weather
  signal_type text not null,

  -- Numeric value (e.g. sleep hours, HRV ms, step count)
  value_numeric numeric,

  -- String value (e.g. weather condition)
  value_text text,

  -- Raw data blob from source
  raw_data jsonb default '{}'
);

-- ============================================================
-- DEVICE TOKENS
-- APNs push tokens. Written by the client (RLS: own rows only),
-- read by the send-push Edge Function using the service role key,
-- which bypasses RLS entirely — that's the trust boundary: a
-- regular user can register/remove their own token but can never
-- read anyone else's, only the trusted server-side function can.
-- ============================================================
create table public.device_tokens (
  id uuid default uuid_generate_v4() primary key,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,

  -- Hex-encoded APNs device token
  token text not null,

  -- sandbox (Debug/TestFlight-via-Xcode) | production (App Store/TestFlight)
  environment text not null default 'sandbox',

  unique (user_id, token)
);

create index idx_device_tokens_user on public.device_tokens(user_id);

-- ============================================================
-- NUTRITION LOGS
-- Phase 2: manually logged meals feed today's macro summary
-- into the AI context snapshot and the Progress tab.
-- ============================================================
create table public.nutrition_logs (
  id uuid default uuid_generate_v4() primary key,
  logged_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,

  -- Meal type: breakfast | lunch | dinner | snack
  meal_type text not null default 'snack',

  calories int not null default 0,
  protein_g int not null default 0,
  carbs_g int not null default 0,
  fat_g int not null default 0,

  notes text
);

create index idx_nutrition_user_logged_at
  on public.nutrition_logs(user_id, logged_at);

-- ============================================================
-- COACH MESSAGES
-- Chat history between user and AI coach
-- ============================================================
create table public.coach_messages (
  id uuid default uuid_generate_v4() primary key,
  created_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,

  -- role: user | assistant
  role text not null,
  content text not null,

  -- Optional metadata (e.g. workout suggestion embedded in message)
  metadata jsonb default '{}'
);

-- ============================================================
-- PROGRESS PHOTOS
-- ============================================================
create table public.progress_photos (
  id uuid default uuid_generate_v4() primary key,
  created_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,

  -- Storage path in Supabase Storage bucket
  storage_path text not null,

  -- Optional note
  note text,

  -- Body weight at time of photo (optional)
  weight_kg numeric,

  -- Visibility: private (default) | shared
  visibility text default 'private'
);

-- ============================================================
-- PERSONAL RECORDS
-- Tracks PRs per exercise per user
-- ============================================================
create table public.personal_records (
  id uuid default uuid_generate_v4() primary key,
  achieved_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,
  exercise_id uuid references public.exercises(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,

  -- PR type: weight | reps | duration | distance
  pr_type text not null,
  value numeric not null,
  unit text -- kg | lbs | reps | seconds | meters
);

-- ============================================================
-- USAGE TRACKING
-- Tracks API calls per user for free tier enforcement
-- and cost monitoring
-- ============================================================
create table public.usage_tracking (
  id uuid default uuid_generate_v4() primary key,
  created_at timestamp with time zone default now(),

  user_id uuid references public.profiles(id) on delete cascade,

  -- Date of usage (for daily limit resets)
  usage_date date not null default current_date,

  -- Task type mirrors routing logic
  -- chat_message | workout_generation | daily_briefing
  -- | logging | notification
  task_type text not null,

  -- Model used: haiku | sonnet
  model_used text not null,

  -- Token counts for cost tracking
  input_tokens int default 0,
  output_tokens int default 0,

  -- Approximate cost in USD (for internal monitoring)
  estimated_cost_usd numeric(10, 6) default 0
);

-- Composite index for fast daily limit lookups
create index idx_usage_user_date
  on public.usage_tracking(user_id, usage_date, task_type);

-- RLS
alter table public.usage_tracking enable row level security;
create policy "Users can view own usage"
  on public.usage_tracking for select using (auth.uid() = user_id);
create policy "Service role can insert usage"
  on public.usage_tracking for insert with check (auth.uid() = user_id);

-- ============================================================
-- USAGE LIMITS VIEW
-- Easy lookup of today's usage vs limits per user
-- ============================================================
create or replace view public.daily_usage_summary as
select
  user_id,
  usage_date,
  sum(case when task_type = 'chat_message' then 1 else 0 end)
    as chat_messages_today,
  sum(case when task_type = 'workout_generation' then 1 else 0 end)
    as workouts_generated_today,
  sum(case when task_type = 'daily_briefing' then 1 else 0 end)
    as briefings_today,
  sum(estimated_cost_usd) as total_cost_today_usd
from public.usage_tracking
where usage_date = current_date
group by user_id, usage_date;


-- Users can only access their own data
-- ============================================================
alter table public.profiles enable row level security;
alter table public.workouts enable row level security;
alter table public.workout_plans enable row level security;
alter table public.sessions enable row level security;
alter table public.context_signals enable row level security;
alter table public.coach_messages enable row level security;
alter table public.progress_photos enable row level security;
alter table public.personal_records enable row level security;
alter table public.nutrition_logs enable row level security;
alter table public.device_tokens enable row level security;

-- Profiles
create policy "Users can view own profile"
  on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);
create policy "Users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

-- Workouts
create policy "Users can manage own workouts"
  on public.workouts for all using (auth.uid() = user_id);

-- Workout Plans
create policy "Users can manage own plans"
  on public.workout_plans for all using (auth.uid() = user_id);

-- Sessions
create policy "Users can manage own sessions"
  on public.sessions for all using (auth.uid() = user_id);

-- Context Signals
create policy "Users can manage own signals"
  on public.context_signals for all using (auth.uid() = user_id);

-- Coach Messages
create policy "Users can manage own messages"
  on public.coach_messages for all using (auth.uid() = user_id);

-- Progress Photos
create policy "Users can manage own photos"
  on public.progress_photos for all using (auth.uid() = user_id);

-- Personal Records
create policy "Users can manage own PRs"
  on public.personal_records for all using (auth.uid() = user_id);

-- Nutrition Logs
create policy "Users can manage own nutrition logs"
  on public.nutrition_logs for all using (auth.uid() = user_id);

-- Device Tokens — client can register/remove its own token only.
-- The send-push Edge Function reads across all users via the
-- service role key, which bypasses RLS by design.
create policy "Users can manage own device tokens"
  on public.device_tokens for all using (auth.uid() = user_id);

-- Exercises are public read
alter table public.exercises enable row level security;
create policy "Exercises are publicly readable"
  on public.exercises for select using (true);

-- ============================================================
-- AUTO-UPDATE updated_at TRIGGER
-- ============================================================
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger on_profiles_updated
  before update on public.profiles
  for each row execute procedure public.handle_updated_at();

create trigger on_plans_updated
  before update on public.workout_plans
  for each row execute procedure public.handle_updated_at();

create trigger on_device_tokens_updated
  before update on public.device_tokens
  for each row execute procedure public.handle_updated_at();

-- ============================================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- ============================================================
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
