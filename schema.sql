-- 새 프로젝트의 Supabase SQL Editor에서 실행하세요.
-- 기존 객체가 같은 이름으로 존재하면 먼저 검토하세요. DROP 없이 생성합니다.
create table public.kanban_boards (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tasks jsonb not null default '[]'::jsonb check (jsonb_typeof(tasks) = 'array'),
  revision integer not null default 0 check (revision >= 0),
  updated_at timestamptz not null default now()
);
alter table public.kanban_boards enable row level security;
-- 클라이언트는 조회만 직접 수행합니다. 쓰기는 검증된 RPC만 허용합니다.
revoke all on public.kanban_boards from anon, authenticated;
grant select on public.kanban_boards to authenticated;
create policy "Users read their own board" on public.kanban_boards
  for select to authenticated using ((select auth.uid()) = user_id);

create function public.save_kanban_board(p_tasks jsonb, p_expected_revision integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_revision integer;
  v_task jsonb;
  v_date date;
  v_ids text[] := array[]::text[];
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_expected_revision is null or p_expected_revision < 0 then raise exception 'INVALID_REVISION'; end if;
  if p_tasks is null or jsonb_typeof(p_tasks) <> 'array' then raise exception 'INVALID_TASKS'; end if;
  if jsonb_array_length(p_tasks) > 10000 or octet_length(p_tasks::text) > 20000000 then raise exception 'BOARD_TOO_LARGE'; end if;
  for v_task in select value from jsonb_array_elements(p_tasks) loop
    if jsonb_typeof(v_task) <> 'object' or not (v_task ?& array['id','title','description','status','priority','due','created','order']) then raise exception 'INVALID_TASK'; end if;
    if jsonb_typeof(v_task->'id') <> 'string' or length(v_task->>'id') not between 1 and 200 or (v_task->>'id') = any(v_ids) then raise exception 'INVALID_ID'; end if;
    v_ids := array_append(v_ids, v_task->>'id');
    if jsonb_typeof(v_task->'title') <> 'string' or length(btrim(v_task->>'title')) not between 1 and 160 then raise exception 'INVALID_TITLE'; end if;
    if jsonb_typeof(v_task->'description') <> 'string' or length(v_task->>'description') > 10000 then raise exception 'INVALID_DESCRIPTION'; end if;
    if jsonb_typeof(v_task->'status') <> 'string' or (v_task->>'status') not in ('todo','doing','done') then raise exception 'INVALID_STATUS'; end if;
    if jsonb_typeof(v_task->'priority') <> 'string' or (v_task->>'priority') not in ('low','medium','high') then raise exception 'INVALID_PRIORITY'; end if;
    if jsonb_typeof(v_task->'created') <> 'number' or jsonb_typeof(v_task->'order') <> 'number' then raise exception 'INVALID_NUMBER'; end if;
    if jsonb_typeof(v_task->'due') <> 'string' then raise exception 'INVALID_DUE'; end if;
    if (v_task->>'due') <> '' then
      if (v_task->>'due') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'INVALID_DUE'; end if;
      v_date := (v_task->>'due')::date;
      if to_char(v_date,'YYYY-MM-DD') <> (v_task->>'due') then raise exception 'INVALID_DUE'; end if;
    end if;
  end loop;
  -- 처음 저장하는 동시 요청도 한 행 잠금으로 직렬화합니다.
  insert into public.kanban_boards(user_id) values(v_user) on conflict(user_id) do nothing;
  select revision into v_revision from public.kanban_boards where user_id = v_user for update;
  if v_revision <> p_expected_revision then raise exception 'BOARD_CONFLICT: reload required'; end if;
  update public.kanban_boards set tasks=p_tasks, revision=revision+1, updated_at=now() where user_id=v_user returning revision into v_revision;
  return v_revision;
end;
$$;
revoke all on function public.save_kanban_board(jsonb, integer) from public, anon;
grant execute on function public.save_kanban_board(jsonb, integer) to authenticated;
comment on function public.save_kanban_board(jsonb, integer) is 'Writes only auth.uid() board; validates data and performs optimistic concurrency control.';
