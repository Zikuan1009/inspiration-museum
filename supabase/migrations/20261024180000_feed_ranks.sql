-- 首页推送顺序。同一天、同一画像、同一批帖子不重复调用模型。
create table if not exists public.feed_ranks (
  user_id uuid primary key references auth.users (id) on delete cascade,
  feed_date date not null,
  portrait_stamp text not null default '',
  catalog_stamp text not null default '',
  post_ids uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.feed_ranks enable row level security;

drop policy if exists "read own feed rank" on public.feed_ranks;
create policy "read own feed rank"
  on public.feed_ranks
  for select
  to authenticated
  using (auth.uid() = user_id);

grant select on public.feed_ranks to authenticated;
grant all on public.feed_ranks to service_role;
