alter table public.daily_letters
  add column if not exists city_name text not null default '',
  add column if not exists city_country text not null default '',
  add column if not exists building_name text not null default '',
  add column if not exists building_city text not null default '',
  add column if not exists film_title text not null default '',
  add column if not exists film_director text not null default '',
  add column if not exists book_title text not null default '',
  add column if not exists book_author text not null default '';
