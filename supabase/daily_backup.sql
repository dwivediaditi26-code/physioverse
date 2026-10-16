-- PhysioVerse: guaranteed DAILY server-side backup (runs inside Supabase, no computer/browser needed).
-- Run ONCE in Supabase → SQL Editor, AFTER clinic_data_history.sql. Safe to re-run.
--
-- 1) Turns on pg_cron (Supabase's built-in scheduler; available on the free plan).
-- 2) Every day at 02:00 India time (20:30 UTC) copies the current clinic data into clinic_data_history
--    with reason 'daily'. Daily snapshots are kept 90 days; the in-between ones ('periodic' / 'decreased')
--    are kept 14 days.

create extension if not exists pg_cron;

create or replace function public.clinic_data_prune() returns void
language sql security definer set search_path = public as $$
  delete from clinic_data_history
   where (reason is distinct from 'daily' and saved_at < now() - interval '14 days')
      or saved_at < now() - interval '90 days';
$$;

-- same trigger as before, but pruning now goes through the function above
create or replace function public.clinic_data_snapshot() returns trigger
language plpgsql security definer set search_path = public as $$
declare why text;
begin
  if old.data is null then return new; end if;
  if _jl(new.data->'assessments') < _jl(old.data->'assessments') then why := 'assessments decreased';
  elsif _jl(new.data->'plans') < _jl(old.data->'plans') then why := 'plans decreased';
  elsif _jl(new.data->'patients') < _jl(old.data->'patients') then why := 'patients decreased';
  elsif _jl(new.data->'invoices') < _jl(old.data->'invoices') then why := 'invoices decreased';
  elsif _jl(new.data->'appointments') < _jl(old.data->'appointments') then why := 'appointments decreased';
  elsif not exists (select 1 from clinic_data_history h where h.row_id = old.id and h.saved_at > now() - interval '30 minutes') then why := 'periodic';
  end if;
  if why is not null then
    insert into clinic_data_history (row_id, updated_at, reason, data) values (old.id, old.updated_at, why, old.data);
    perform clinic_data_prune();
  end if;
  return new;
end $$;

select cron.unschedule('clinic-daily-backup') where exists (select 1 from cron.job where jobname = 'clinic-daily-backup');
select cron.schedule('clinic-daily-backup', '30 20 * * *', $$
  insert into public.clinic_data_history (row_id, updated_at, reason, data)
  select id, updated_at, 'daily', data from public.clinic_data where id = 'main' and data is not null;
  select public.clinic_data_prune();
$$);

-- Check it is scheduled:   select jobname, schedule, active from cron.job;
-- See daily backups:       select id, saved_at, reason, _jl(data->'patients') patients, _jl(data->'assessments') assessments from clinic_data_history where reason='daily' order by saved_at desc;
-- Check the space used:    select pg_size_pretty(pg_total_relation_size('clinic_data_history'));
