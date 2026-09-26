create table public.account_auth_rate_limits (
    scope text not null,
    subject_hash text not null,
    window_started_at timestamptz not null default now(),
    request_count integer not null default 0 check (request_count >= 0),
    primary key (scope, subject_hash),
    check (char_length(scope) between 1 and 64),
    check (subject_hash ~ '^[0-9a-f]{64}$')
);

alter table public.account_auth_rate_limits enable row level security;
revoke all on table public.account_auth_rate_limits from public, anon, authenticated;

create index account_auth_rate_limits_window_started_at_idx
on public.account_auth_rate_limits (window_started_at);

create function public.consume_account_auth_rate_limit(
    p_scope text,
    p_subject_hash text,
    p_limit integer,
    p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_count integer;
begin
    if char_length(p_scope) not between 1 and 64
       or p_subject_hash !~ '^[0-9a-f]{64}$'
       or p_limit not between 1 and 1000
       or p_window_seconds not between 1 and 86400 then
        raise exception 'invalid rate limit parameters' using errcode = '22023';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(p_scope || ':' || p_subject_hash, 0));

    insert into public.account_auth_rate_limits (
        scope,
        subject_hash,
        window_started_at,
        request_count
    )
    values (p_scope, p_subject_hash, now(), 1)
    on conflict (scope, subject_hash) do update
    set
        window_started_at = case
            when account_auth_rate_limits.window_started_at
                 <= now() - make_interval(secs => p_window_seconds)
            then now()
            else account_auth_rate_limits.window_started_at
        end,
        request_count = case
            when account_auth_rate_limits.window_started_at
                 <= now() - make_interval(secs => p_window_seconds)
            then 1
            else account_auth_rate_limits.request_count + 1
        end
    returning request_count into current_count;

    delete from public.account_auth_rate_limits
    where ctid in (
        select ctid
        from public.account_auth_rate_limits
        where window_started_at < now() - interval '1 day'
        limit 100
    );

    return current_count <= p_limit;
end;
$$;

revoke all on function public.consume_account_auth_rate_limit(text, text, integer, integer)
from public, anon, authenticated;
grant execute on function public.consume_account_auth_rate_limit(text, text, integer, integer)
to service_role;
