# Off-site daily backup (private GitHub repo)

Saves a compressed copy of all clinic data to a **private** GitHub repo every day, so a copy exists
outside Supabase and outside the client's computer.

1. GitHub → **New repository** → name `physioverse-backups` → **Private** (must be private!).
2. In that repo create `.github/workflows/backup.yml` and paste the contents of `backup.yml` from this folder.
3. Repo → **Settings → Secrets and variables → Actions → New repository secret**, add two:
   - `SUPABASE_URL` = `https://mtbrpfylkdpcvijhmcgg.supabase.co`
   - `SUPABASE_SERVICE_KEY` = Supabase dashboard → **Project Settings → API Keys → service_role** (secret key).
     This key bypasses all security — keep it only in this secret, never in code, chat or the public repo.
4. Repo → **Actions → Daily clinic backup → Run workflow** once to test. A `backups/clinic-YYYY-MM-DD.json.gz` file appears.
5. GitHub emails you automatically if a daily run ever fails.

Restore: download the `.json.gz`, unzip to `.json`, then in the app → Settings → *Restore data only (.json)*.
