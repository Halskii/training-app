-- Self-reported training level, used by the AI planner to scope programming.
alter table athlete_files
  add column if not exists training_level text
  check (training_level in ('beginner', 'intermediate', 'seasoned'));
