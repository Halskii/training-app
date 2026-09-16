-- Core schema: users, athlete file, macrocycles/blocks, logs, goals, supplements.
-- Run this in the Supabase SQL editor (or via `supabase db push` once linked).

create table if not exists athlete_files (
  user_id uuid primary key references auth.users(id) on delete cascade,
  training_age_years numeric,
  rpe_trend_notes text,
  programming_style_notes text,
  last_updated timestamptz not null default now()
);

create table if not exists goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  description text not null,
  kind text not null check (kind in ('long_term', 'phase', 'competition')),
  target_date date,
  competition_events text[],
  subtasks text[] default '{}',
  created_at timestamptz not null default now()
);

create table if not exists injury_flags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  area text not null,
  note text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists macrocycles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  skeleton jsonb not null, -- MacrocycleSkeleton, including all 3 block shapes
  goal_ids uuid[] default '{}',
  created_at timestamptz not null default now()
);

create table if not exists blocks (
  id uuid primary key default gen_random_uuid(),
  macrocycle_id uuid not null references macrocycles(id) on delete cascade,
  phase text not null check (phase in ('accumulation', 'intensification', 'realization')),
  week_start int not null,
  week_end int not null,
  detail jsonb, -- DetailedBlock once generated; null until detailed
  coach_note text,
  created_at timestamptz not null default now()
);

create table if not exists workout_logs (
  id uuid primary key default gen_random_uuid(),
  block_id uuid not null references blocks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day_index int not null,
  exercise text not null,
  sets int,
  reps text,
  load text,
  rpe numeric,
  notes text,
  logged_at timestamptz not null default now()
);

create table if not exists feedback_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  block_id uuid references blocks(id) on delete set null,
  kind text not null check (kind in ('injury', 'note', 'plan_diff')),
  content text not null,
  created_at timestamptz not null default now()
);

create table if not exists supplements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text, -- e.g. 'supplement' | 'medication' | 'ped'
  dosage text,
  schedule text,
  active boolean not null default true
);

create table if not exists supplement_logs (
  id uuid primary key default gen_random_uuid(),
  supplement_id uuid not null references supplements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  taken_at timestamptz not null default now()
);

-- Row Level Security: every table is user-scoped.
alter table athlete_files enable row level security;
alter table goals enable row level security;
alter table injury_flags enable row level security;
alter table macrocycles enable row level security;
alter table blocks enable row level security;
alter table workout_logs enable row level security;
alter table feedback_events enable row level security;
alter table supplements enable row level security;
alter table supplement_logs enable row level security;

create policy "own athlete_files" on athlete_files for all using (auth.uid() = user_id);
create policy "own goals" on goals for all using (auth.uid() = user_id);
create policy "own injury_flags" on injury_flags for all using (auth.uid() = user_id);
create policy "own macrocycles" on macrocycles for all using (auth.uid() = user_id);
create policy "own blocks" on blocks for all using (
  auth.uid() = (select user_id from macrocycles where macrocycles.id = blocks.macrocycle_id)
);
create policy "own workout_logs" on workout_logs for all using (auth.uid() = user_id);
create policy "own feedback_events" on feedback_events for all using (auth.uid() = user_id);
create policy "own supplements" on supplements for all using (auth.uid() = user_id);
create policy "own supplement_logs" on supplement_logs for all using (auth.uid() = user_id);
