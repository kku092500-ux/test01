-- 게시판 테이블 + 권한 정책
-- 사용법: Supabase 대시보드 > SQL Editor > New query 에 전체를 붙여넣고 Run
-- 여러 번 실행해도 안전합니다.

create table if not exists public.posts (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  author_name text not null default '',
  title       text not null check (char_length(title) between 1 and 100),
  content     text not null check (char_length(content) between 1 and 5000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists posts_created_at_idx on public.posts (created_at desc);

-- 작성자/시각은 브라우저가 보낸 값을 믿지 않고 서버에서 정합니다.
-- 이메일 전체를 공개하지 않도록 앞 2글자 + *** 로 가립니다.
create or replace function public.posts_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.user_id     := auth.uid();
    new.author_name := left(split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1), 2) || '***';
    new.created_at  := now();
  else
    new.user_id     := old.user_id;
    new.author_name := old.author_name;
    new.created_at  := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists posts_before_write on public.posts;
create trigger posts_before_write
  before insert or update on public.posts
  for each row execute function public.posts_before_write();

-- 행 수준 보안(RLS): 켜면 아래 정책에 허용된 동작만 가능합니다.
alter table public.posts enable row level security;

drop policy if exists "posts_select_all"  on public.posts;
drop policy if exists "posts_insert_own"  on public.posts;
drop policy if exists "posts_update_own"  on public.posts;
drop policy if exists "posts_delete_own"  on public.posts;

create policy "posts_select_all" on public.posts
  for select to anon, authenticated using (true);

create policy "posts_insert_own" on public.posts
  for insert to authenticated with check (auth.uid() = user_id);

create policy "posts_update_own" on public.posts
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "posts_delete_own" on public.posts
  for delete to authenticated using (auth.uid() = user_id);
