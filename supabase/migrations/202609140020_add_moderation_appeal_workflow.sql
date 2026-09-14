alter table public.user_notices drop constraint user_notices_kind_check;
alter table public.user_notices add constraint user_notices_kind_check
check (kind in ('moderation_action', 'report_result', 'appeal_result'));

create function public.action_user_report(
    p_report_id uuid,
    p_kind text,
    p_reason text,
    p_ends_at timestamptz default null,
    p_note text default ''
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare target_user_id uuid; sanction_id uuid;
begin
    if not public.is_content_moderator() then
        raise exception 'moderator access required' using errcode = '42501';
    end if;
    select target_id into target_user_id from public.content_reports
    where id = p_report_id and target_type = 'user' for update;
    if not found then raise exception 'user report not found' using errcode = 'P0002'; end if;

    perform public.review_content_report(p_report_id, 'actioned', p_note);
    sanction_id := public.create_account_sanction(
        target_user_id, p_kind, p_reason, p_ends_at, p_report_id
    );
    insert into public.user_notices (recipient_id, report_id, kind, title, body)
    values (
        target_user_id, p_report_id, 'moderation_action', '계정 ' ||
        case p_kind when 'warning' then '경고' when 'restriction' then '이용 제한' else '정지' end || ' 안내',
        btrim(p_reason)
    ) on conflict (recipient_id, report_id, kind) do update
      set title = excluded.title, body = excluded.body, read_at = null, created_at = now();
    return sanction_id;
end; $$;

revoke all on function public.action_user_report(uuid, text, text, timestamptz, text) from public, anon;
grant execute on function public.action_user_report(uuid, text, text, timestamptz, text) to authenticated;

create function public.fetch_moderation_appeals(p_status text default null, p_limit integer default 100)
returns table (
    id uuid, sanction_id uuid, user_id uuid, user_name text, user_handle text,
    sanction_kind text, sanction_reason text, appeal_body text, appeal_status text,
    moderator_note text, created_at timestamptz, reviewed_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
begin
    if not public.is_content_moderator() then
        raise exception 'moderator access required' using errcode = '42501';
    end if;
    return query
    select appeal.id, appeal.sanction_id, appeal.user_id, profile.display_name,
        coalesce(profile.handle, ''), sanction.kind, sanction.reason, appeal.body,
        appeal.status, appeal.moderator_note, appeal.created_at, appeal.reviewed_at
    from public.account_sanction_appeals appeal
    join public.account_sanctions sanction on sanction.id = appeal.sanction_id
    join public.profiles profile on profile.id = appeal.user_id
    where p_status is null or appeal.status = p_status
    order by case appeal.status when 'pending' then 0 when 'reviewing' then 1 else 2 end,
        appeal.created_at asc
    limit least(greatest(p_limit, 1), 200);
end; $$;

revoke all on function public.fetch_moderation_appeals(text, integer) from public, anon;
grant execute on function public.fetch_moderation_appeals(text, integer) to authenticated;

create or replace function public.review_account_sanction_appeal(
    p_appeal_id uuid, p_status text, p_note text default ''
) returns void language plpgsql security definer set search_path = '' as $$
declare current_appeal public.account_sanction_appeals%rowtype; report_id uuid;
begin
    if not public.is_content_moderator() then raise exception 'moderator access required' using errcode = '42501'; end if;
    if p_status not in ('reviewing', 'accepted', 'rejected') then raise exception 'invalid appeal status' using errcode = '22023'; end if;
    if char_length(btrim(coalesce(p_note, ''))) > 1000 then raise exception 'moderator note is too long' using errcode = '22001'; end if;
    select * into current_appeal from public.account_sanction_appeals where id = p_appeal_id for update;
    if not found then raise exception 'appeal not found' using errcode = 'P0002'; end if;
    update public.account_sanction_appeals set status = p_status, moderator_note = btrim(coalesce(p_note, '')),
        reviewed_by = (select auth.uid()), reviewed_at = case when p_status in ('accepted', 'rejected') then now() else null end,
        updated_at = now() where id = p_appeal_id;
    if p_status = 'accepted' then update public.account_sanctions set lifted_at = coalesce(lifted_at, now()) where id = current_appeal.sanction_id; end if;
    if p_status in ('accepted', 'rejected') then
        select source_report_id into report_id from public.account_sanctions where id = current_appeal.sanction_id;
        insert into public.user_notices (recipient_id, report_id, kind, title, body)
        values (current_appeal.user_id, report_id, 'appeal_result',
            case p_status when 'accepted' then '이의 제기 인용' else '이의 제기 기각' end,
            case when btrim(coalesce(p_note, '')) = '' then
                case p_status when 'accepted' then '제재를 해제했어요.' else '기존 제재를 유지합니다.' end
            else btrim(p_note) end);
    end if;
end; $$;
