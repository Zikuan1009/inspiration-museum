alter table public.profiles
  add column if not exists breakout_ratio integer not null default 30;
