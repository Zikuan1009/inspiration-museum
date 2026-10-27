alter table public.profiles
  add column if not exists hobbies text not null default '',
  add column if not exists personality text not null default '',
  add column if not exists occupation text not null default '',
  add column if not exists letter_forms text[] not null default array['keyword', 'quote'];

alter table public.daily_letters
  add column if not exists quote_author text not null default '',
  add column if not exists music_title text not null default '',
  add column if not exists music_artist text not null default '',
  add column if not exists image_url text not null default '',
  add column if not exists forms text[] not null default '{}';

drop policy if exists "delete own daily letter" on public.daily_letters;
create policy "delete own daily letter"
  on public.daily_letters
  for delete
  to authenticated
  using (auth.uid() = user_id);
