create table if not exists public.letter_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  letter_date date not null,
  letter jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, letter_date)
);

alter table public.letter_drafts enable row level security;

drop policy if exists "read own letter drafts" on public.letter_drafts;
create policy "read own letter drafts"
  on public.letter_drafts
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "insert own letter drafts" on public.letter_drafts;
create policy "insert own letter drafts"
  on public.letter_drafts
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "update own letter drafts" on public.letter_drafts;
create policy "update own letter drafts"
  on public.letter_drafts
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "delete own letter drafts" on public.letter_drafts;
create policy "delete own letter drafts"
  on public.letter_drafts
  for delete
  to authenticated
  using (auth.uid() = user_id);

notify pgrst, 'reload schema';
