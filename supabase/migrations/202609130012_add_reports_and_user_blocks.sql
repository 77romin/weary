create table public.content_reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references public.profiles(id) on delete cascade,
    target_type text not null check (target_type in ('post', 'listing', 'message', 'user')),
    target_id uuid not null,
    reason text not null check (reason in ('spam', 'fraud', 'harassment', 'inappropriate', 'other')),
    details text not null default '' check (char_length(details) <= 1000),
    status text not null default 'pending'
        check (status in ('pending', 'reviewing', 'dismissed', 'actioned')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (reporter_id, target_type, target_id)
);

create index content_reports_status_created_idx
on public.content_reports (status, created_at);

create trigger content_reports_set_updated_at
before update on public.content_reports
for each row execute procedure public.set_updated_at();

create table public.user_blocks (
    blocker_id uuid not null references public.profiles(id) on delete cascade,
    blocked_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);

create index user_blocks_blocked_idx
on public.user_blocks (blocked_id, created_at desc);

alter table public.content_reports enable row level security;
alter table public.user_blocks enable row level security;

revoke all on table public.content_reports from anon, authenticated;
revoke all on table public.user_blocks from anon, authenticated;
grant select, insert on table public.content_reports to authenticated;
grant select, insert, delete on table public.user_blocks to authenticated;

create policy "users can read their own reports"
on public.content_reports for select
to authenticated
using (reporter_id = (select auth.uid()));

create policy "users can submit their own reports"
on public.content_reports for insert
to authenticated
with check (
    reporter_id = (select auth.uid())
    and status = 'pending'
);

create policy "users can read their own blocks"
on public.user_blocks for select
to authenticated
using (blocker_id = (select auth.uid()));

create policy "users can create their own blocks"
on public.user_blocks for insert
to authenticated
with check (
    blocker_id = (select auth.uid())
    and blocked_id <> (select auth.uid())
);

create policy "users can remove their own blocks"
on public.user_blocks for delete
to authenticated
using (blocker_id = (select auth.uid()));

do $$
declare
    table_name text;
begin
    foreach table_name in array array[
        'content_reports',
        'user_blocks'
    ]
    loop
        if not exists (
            select 1
            from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = table_name
        ) then
            execute format(
                'alter publication supabase_realtime add table public.%I',
                table_name
            );
        end if;
    end loop;
end;
$$;
