-- 提前写好的每日来信。打开信封时只读，不在这里调用模型。
create table if not exists public.daily_letters (
  user_id uuid not null references auth.users (id) on delete cascade,
  letter_date date not null,
  theme_name text not null default '',
  sub_theme_name text not null default '',
  keyword text not null,
  quote text not null,
  why_today text not null default '',
  created_at timestamptz not null default now(),
  primary key (user_id, letter_date)
);

alter table public.daily_letters enable row level security;

drop policy if exists "read own daily letter" on public.daily_letters;
create policy "read own daily letter"
  on public.daily_letters
  for select
  to authenticated
  using (auth.uid() = user_id);
