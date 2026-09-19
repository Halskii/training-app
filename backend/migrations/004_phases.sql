-- Each plan is one 12-week training phase: track when it started and which phase it is,
-- so the app can show "Week 3 of 12" and offer the next phase when it ends.
alter table macrocycles add column if not exists start_date date;
update macrocycles set start_date = created_at::date where start_date is null;
alter table macrocycles alter column start_date set default current_date;
alter table macrocycles alter column start_date set not null;

alter table macrocycles add column if not exists phase_number int not null default 1;
