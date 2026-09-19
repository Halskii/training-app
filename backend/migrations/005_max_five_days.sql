-- Training days per week is limited to 2-5. Cap anyone saved with 6 or 7 first,
-- then tighten the constraint added in 003.
update athlete_files set training_days_per_week = 5 where training_days_per_week > 5;

alter table athlete_files drop constraint if exists athlete_files_training_days_per_week_check;
alter table athlete_files
  add constraint athlete_files_training_days_per_week_check
  check (training_days_per_week between 2 and 5);
