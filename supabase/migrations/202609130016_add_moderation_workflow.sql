create table public.staff_roles (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    role text not null check (role in ('moderator', 'admin')),
    granted_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

alter table public.staff_roles enable row level security;
revoke all on table public.staff_roles from public, anon, authenticated;
grant select on table public.staff_roles to authenticated;

create policy "staff can read their own role"
on public.staff_roles for select
to authenticated
using (user_id = (select auth.uid()));

create function public.is_content_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.staff_roles
        where user_id = (select auth.uid())
          and role in ('moderator', 'admin')
    );
$$;

revoke all on function public.is_content_moderator() from public, anon;
grant execute on function public.is_content_moderator() to authenticated;

alter table public.content_reports
    add column reviewed_by uuid references public.profiles(id) on delete set null,
    add column reviewed_at timestamptz,
    add column moderator_note text not null default ''
        check (char_length(moderator_note) <= 1000);

create table public.content_report_actions (
    id uuid primary key default gen_random_uuid(),
    report_id uuid not null references public.content_reports(id) on delete cascade,
    moderator_id uuid references public.profiles(id) on delete set null,
    previous_status text not null
        check (previous_status in ('pending', 'reviewing', 'dismissed', 'actioned')),
    next_status text not null
        check (next_status in ('pending', 'reviewing', 'dismissed', 'actioned')),
    note text not null default '' check (char_length(note) <= 1000),
    created_at timestamptz not null default now()
);

create index content_report_actions_report_created_idx
on public.content_report_actions (report_id, created_at desc);

alter table public.content_report_actions enable row level security;
revoke all on table public.content_report_actions from public, anon, authenticated;
grant select on table public.content_report_actions to authenticated;

create policy "staff can read moderation actions"
on public.content_report_actions for select
to authenticated
using ((select public.is_content_moderator()));

create policy "staff can read all reports"
on public.content_reports for select
to authenticated
using ((select public.is_content_moderator()));

drop policy "users can remove their own reports" on public.content_reports;
create policy "users can remove pending own reports"
on public.content_reports for delete
to authenticated
using (
    reporter_id = (select auth.uid())
    and status = 'pending'
);

create function public.fetch_moderation_reports(
    p_status text default null,
    p_limit integer default 100
)
returns table (
    id uuid,
    reporter_id uuid,
    reporter_name text,
    reporter_handle text,
    target_type text,
    target_id uuid,
    target_summary text,
    reason text,
    details text,
    report_status text,
    moderator_note text,
    created_at timestamptz,
    updated_at timestamptz,
    reviewed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not public.is_content_moderator() then
        raise exception 'moderator access required' using errcode = '42501';
    end if;

    if p_status is not null
       and p_status not in ('pending', 'reviewing', 'dismissed', 'actioned') then
        raise exception 'invalid report status' using errcode = '22023';
    end if;

    return query
    select
        report.id,
        report.reporter_id,
        reporter.display_name,
        coalesce(reporter.handle, ''),
        report.target_type,
        report.target_id,
        coalesce(
            case report.target_type
                when 'post' then (
                    select left(post.caption, 180)
                    from public.posts as post
                    where post.id = report.target_id
                )
                when 'listing' then (
                    select left(listing.title || case
                        when listing.description = '' then ''
                        else ' · ' || listing.description
                    end, 180)
                    from public.market_listings as listing
                    where listing.id = report.target_id
                )
                when 'message' then (
                    select left(message.body, 180)
                    from public.market_messages as message
                    where message.id = report.target_id
                )
                when 'user' then (
                    select profile.display_name || ' (@' || coalesce(profile.handle, 'weary') || ')'
                    from public.profiles as profile
                    where profile.id = report.target_id
                )
            end,
            '삭제되었거나 접근할 수 없는 대상'
        ),
        report.reason,
        report.details,
        report.status,
        report.moderator_note,
        report.created_at,
        report.updated_at,
        report.reviewed_at
    from public.content_reports as report
    join public.profiles as reporter on reporter.id = report.reporter_id
    where p_status is null or report.status = p_status
    order by
        case report.status
            when 'pending' then 0
            when 'reviewing' then 1
            else 2
        end,
        report.created_at asc
    limit least(greatest(p_limit, 1), 200);
end;
$$;

revoke all on function public.fetch_moderation_reports(text, integer) from public, anon;
grant execute on function public.fetch_moderation_reports(text, integer) to authenticated;

create function public.review_content_report(
    p_report_id uuid,
    p_status text,
    p_note text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_report public.content_reports%rowtype;
    normalized_note text := btrim(coalesce(p_note, ''));
begin
    if not public.is_content_moderator() then
        raise exception 'moderator access required' using errcode = '42501';
    end if;

    if p_status not in ('pending', 'reviewing', 'dismissed', 'actioned') then
        raise exception 'invalid report status' using errcode = '22023';
    end if;

    if char_length(normalized_note) > 1000 then
        raise exception 'moderator note is too long' using errcode = '22001';
    end if;

    select *
    into current_report
    from public.content_reports
    where id = p_report_id
    for update;

    if not found then
        raise exception 'report not found' using errcode = 'P0002';
    end if;

    update public.content_reports
    set
        status = p_status,
        moderator_note = normalized_note,
        reviewed_by = (select auth.uid()),
        reviewed_at = now()
    where id = p_report_id;

    insert into public.content_report_actions (
        report_id,
        moderator_id,
        previous_status,
        next_status,
        note
    )
    values (
        p_report_id,
        (select auth.uid()),
        current_report.status,
        p_status,
        normalized_note
    );
end;
$$;

revoke all on function public.review_content_report(uuid, text, text) from public, anon;
grant execute on function public.review_content_report(uuid, text, text) to authenticated;
