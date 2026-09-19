-- How many days per week the athlete can train; drives how many day tables a block gets.
alter table athlete_files
  add column if not exists training_days_per_week int
  check (training_days_per_week between 2 and 7);
