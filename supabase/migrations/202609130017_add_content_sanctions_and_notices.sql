alter table public.posts
    add column moderation_report_id uuid references public.content_reports(id) on delete set null;

alter table public.market_listings
    add column moderation_report_id uuid references public.content_reports(id) on delete set null;

create function public.protect_moderation_hidden_content()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if old.moderation_report_id is not null
       and (
           new.status is distinct from old.status
           or new.moderation_report_id is distinct from old.moderation_report_id
       )
       and not public.is_content_moderator() then
        raise exception 'moderated content status cannot be changed by its owner'
            using errcode = '42501';
    end if;
    return new;
end;
$$;

revoke all on function public.protect_moderation_hidden_content() from public, anon, authenticated;

create trigger posts_protect_moderation_hidden
before update of status, moderation_report_id on public.posts
for each row execute procedure public.protect_moderation_hidden_content();

create trigger market_listings_protect_moderation_hidden
before update of status, moderation_report_id on public.market_listings
for each row execute procedure public.protect_moderation_hidden_content();

create table public.user_notices (
    id uuid primary key default gen_random_uuid(),
    recipient_id uuid not null references public.profiles(id) on delete cascade,
    report_id uuid references public.content_reports(id) on delete set null,
    kind text not null check (kind in ('moderation_action', 'report_result')),
    title text not null check (char_length(btrim(title)) between 1 and 120),
    body text not null check (char_length(btrim(body)) between 1 and 1000),
    read_at timestamptz,
    created_at timestamptz not null default now(),
    unique (recipient_id, report_id, kind)
);

create index user_notices_recipient_created_idx
on public.user_notices (recipient_id, created_at desc);

alter table public.user_notices enable row level security;
revoke all on table public.user_notices from public, anon, authenticated;
grant select on table public.user_notices to authenticated;

create policy "users can read their own notices"
on public.user_notices for select
to authenticated
using (recipient_id = (select auth.uid()));

create function public.mark_user_notice_read(p_notice_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
    update public.user_notices
    set read_at = coalesce(read_at, now())
    where id = p_notice_id
      and recipient_id = (select auth.uid());
$$;

revoke all on function public.mark_user_notice_read(uuid) from public, anon;
grant execute on function public.mark_user_notice_read(uuid) to authenticated;

create or replace function public.review_content_report(
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
    target_owner_id uuid;
    target_label text;
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

    if current_report.status = 'actioned' and p_status <> 'actioned' then
        raise exception 'actioned reports require the appeal workflow'
            using errcode = '55000';
    end if;

    if p_status = 'actioned' and current_report.target_type = 'post' then
        update public.posts
        set
            status = 'hidden',
            moderation_report_id = current_report.id
        where id = current_report.target_id
          and status <> 'deleted'
        returning author_id into target_owner_id;
        target_label := '게시물';
    elsif p_status = 'actioned' and current_report.target_type = 'listing' then
        update public.market_listings
        set
            status = 'hidden',
            moderation_report_id = current_report.id
        where id = current_report.target_id
          and status <> 'deleted'
        returning seller_id into target_owner_id;
        target_label := '판매 매물';
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

    if p_status = 'actioned' then
        insert into public.user_notices (
            recipient_id,
            report_id,
            kind,
            title,
            body
        )
        values (
            current_report.reporter_id,
            current_report.id,
            'report_result',
            '신고 처리 완료',
            '신고한 콘텐츠를 검토하고 필요한 조치를 완료했어요.'
        )
        on conflict (recipient_id, report_id, kind) do update
        set
            title = excluded.title,
            body = excluded.body,
            read_at = null,
            created_at = now();

        if target_owner_id is not null
           and target_owner_id <> current_report.reporter_id then
            insert into public.user_notices (
                recipient_id,
                report_id,
                kind,
                title,
                body
            )
            values (
                target_owner_id,
                current_report.id,
                'moderation_action',
                target_label || ' 숨김 처리 안내',
                '커뮤니티 운영 정책 검토 결과 해당 ' || target_label || '이 다른 사용자에게 표시되지 않도록 처리되었어요.'
            )
            on conflict (recipient_id, report_id, kind) do update
            set
                title = excluded.title,
                body = excluded.body,
                read_at = null,
                created_at = now();
        end if;
    elsif p_status = 'dismissed' then
        insert into public.user_notices (
            recipient_id,
            report_id,
            kind,
            title,
            body
        )
        values (
            current_report.reporter_id,
            current_report.id,
            'report_result',
            '신고 검토 완료',
            '신고 내용을 검토했지만 현재 기준으로는 운영 정책 위반을 확인하지 못했어요.'
        )
        on conflict (recipient_id, report_id, kind) do update
        set
            title = excluded.title,
            body = excluded.body,
            read_at = null,
            created_at = now();
    end if;
end;
$$;

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'user_notices'
    ) then
        alter publication supabase_realtime add table public.user_notices;
    end if;
end;
$$;
