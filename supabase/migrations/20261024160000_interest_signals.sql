alter table public.profiles
  add column if not exists observed_note text not null default '',
  add column if not exists interest_stamp text not null default '';

alter table public.daily_letters
  add column if not exists signals_stamp text not null default '';

create table if not exists public.interest_signals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('reflection', 'save', 'like')),
  source_id text not null default '',
  excerpt text not null default '',
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists interest_signals_user_created
  on public.interest_signals (user_id, created_at desc);

alter table public.interest_signals enable row level security;

drop policy if exists "read own interest signals" on public.interest_signals;
create policy "read own interest signals"
  on public.interest_signals
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "insert own interest signals" on public.interest_signals;
create policy "insert own interest signals"
  on public.interest_signals
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "delete own interest signals" on public.interest_signals;
create policy "delete own interest signals"
  on public.interest_signals
  for delete
  to authenticated
  using (auth.uid() = user_id);

grant select, insert, delete on public.interest_signals to authenticated;
grant all on public.interest_signals to service_role;
