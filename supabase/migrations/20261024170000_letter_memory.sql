alter table public.profiles
  add column if not exists letter_memory text not null default '';
