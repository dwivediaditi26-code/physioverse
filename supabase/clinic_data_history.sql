-- PhysioVerse: automatic version history for clinic_data.
-- Run ONCE in Supabase → SQL Editor. Safe to re-run.
--
-- Every time the clinic_data row is updated, the PREVIOUS version is copied into
-- clinic_data_history when either
--   (a) the last snapshot is older than 30 minutes, or
--   (b) the update REMOVES records (fewer patients / assessments / plans / invoices / appointments),
-- so an accidental overwrite or deletion can always be undone. Snapshots older than 14 days are pruned.
-- The history table has RLS on with no policies, so the app (anon/authenticated keys) cannot read it —
-- only you, in the Supabase dashboard.

create table if not exists public.clinic_data_history (
  id         bigserial primary key,
  row_id     text not null,
  saved_at   timestamptz not null default now(),
  updated_at timestamptz,
  reason     text,
  data       jsonb
);
create index if not exists clinic_data_history_saved_idx on public.clinic_data_history (row_id, saved_at desc);
alter table public.clinic_data_history enable row level security;

create or replace function public._jl(j jsonb) returns int
language sql immutable as $$ select case when jsonb_typeof(j) = 'array' then jsonb_array_length(j) else 0 end $$;

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
    delete from clinic_data_history where saved_at < now() - interval '14 days';
  end if;
  return new;
end $$;

drop trigger if exists clinic_data_snapshot_trg on public.clinic_data;
create trigger clinic_data_snapshot_trg before update on public.clinic_data
  for each row execute function public.clinic_data_snapshot();

-- ── HOW TO USE ──────────────────────────────────────────────────────────────
-- 1) See the saved versions (newest first):
--    select id, saved_at, reason, _jl(data->'patients') patients, _jl(data->'assessments') assessments,
--           _jl(data->'plans') plans, _jl(data->'invoices') invoices from clinic_data_history order by saved_at desc;
-- 2) Restore ONLY the assessments of version 123 (keeps everything else as it is now):
--    update clinic_data set data = jsonb_set(data, '{assessments}', (select data->'assessments' from clinic_data_history where id = 123)), updated_at = now() where id = 'main';
-- 3) Restore the whole clinic to version 123 (replaces everything — use with care):
--    update clinic_data set data = (select data from clinic_data_history where id = 123), updated_at = now() where id = 'main';
