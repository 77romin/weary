create table public.account_sanctions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    source_report_id uuid references public.content_reports(id) on delete set null,
    kind text not null check (kind in ('warning', 'restriction', 'suspension')),
    reason text not null check (char_length(btrim(reason)) between 1 and 1000),
    starts_at timestamptz not null default now(),
    ends_at timestamptz,
    lifted_at timestamptz,
    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    check (ends_at is null or ends_at > starts_at)
);

create index account_sanctions_user_created_idx
on public.account_sanctions (user_id, created_at desc);

alter table public.account_sanctions enable row level security;
revoke all on table public.account_sanctions from public, anon, authenticated;
grant select on table public.account_sanctions to authenticated;

create policy "users read own sanctions and staff read all"
on public.account_sanctions for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_content_moderator()));

create table public.account_sanction_appeals (
    id uuid primary key default gen_random_uuid(),
    sanction_id uuid not null references public.account_sanctions(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    body text not null check (char_length(btrim(body)) between 10 and 2000),
    status text not null default 'pending'
        check (status in ('pending', 'reviewing', 'accepted', 'rejected')),
    moderator_note text not null default '' check (char_length(moderator_note) <= 1000),
    reviewed_by uuid references public.profiles(id) on delete set null,
    reviewed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create unique index account_sanction_appeals_open_unique
on public.account_sanction_appeals (sanction_id, user_id)
where status in ('pending', 'reviewing');

alter table public.account_sanction_appeals enable row level security;
revoke all on table public.account_sanction_appeals from public, anon, authenticated;
grant select on table public.account_sanction_appeals to authenticated;

create policy "users read own appeals and staff read all"
on public.account_sanction_appeals for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_content_moderator()));

create function public.submit_account_sanction_appeal(p_sanction_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid; normalized_body text := btrim(coalesce(p_body, ''));
begin
    if char_length(normalized_body) not between 10 and 2000 then
        raise exception 'appeal body must be between 10 and 2000 characters' using errcode = '22023';
    end if;
    if not exists (select 1 from public.account_sanctions where id = p_sanction_id and user_id = (select auth.uid())) then
        raise exception 'sanction not found' using errcode = '42501';
    end if;
    insert into public.account_sanction_appeals (sanction_id, user_id, body)
    values (p_sanction_id, (select auth.uid()), normalized_body) returning id into new_id;
    return new_id;
end; $$;

revoke all on function public.submit_account_sanction_appeal(uuid, text) from public, anon;
grant execute on function public.submit_account_sanction_appeal(uuid, text) to authenticated;

create function public.create_account_sanction(
    p_user_id uuid, p_kind text, p_reason text, p_ends_at timestamptz default null,
    p_source_report_id uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
    if not public.is_content_moderator() then raise exception 'moderator access required' using errcode = '42501'; end if;
    insert into public.account_sanctions (user_id, source_report_id, kind, reason, ends_at, created_by)
    values (p_user_id, p_source_report_id, p_kind, btrim(p_reason), p_ends_at, (select auth.uid()))
    returning id into new_id;
    return new_id;
end; $$;

revoke all on function public.create_account_sanction(uuid, text, text, timestamptz, uuid) from public, anon;
grant execute on function public.create_account_sanction(uuid, text, text, timestamptz, uuid) to authenticated;

create function public.review_account_sanction_appeal(
    p_appeal_id uuid, p_status text, p_note text default ''
) returns void language plpgsql security definer set search_path = '' as $$
declare current_appeal public.account_sanction_appeals%rowtype;
begin
    if not public.is_content_moderator() then raise exception 'moderator access required' using errcode = '42501'; end if;
    if p_status not in ('reviewing', 'accepted', 'rejected') then raise exception 'invalid appeal status' using errcode = '22023'; end if;
    select * into current_appeal from public.account_sanction_appeals where id = p_appeal_id for update;
    if not found then raise exception 'appeal not found' using errcode = 'P0002'; end if;
    update public.account_sanction_appeals set status = p_status, moderator_note = btrim(coalesce(p_note, '')),
        reviewed_by = (select auth.uid()), reviewed_at = case when p_status in ('accepted', 'rejected') then now() else null end,
        updated_at = now() where id = p_appeal_id;
    if p_status = 'accepted' then update public.account_sanctions set lifted_at = coalesce(lifted_at, now()) where id = current_appeal.sanction_id; end if;
end; $$;

revoke all on function public.review_account_sanction_appeal(uuid, text, text) from public, anon;
grant execute on function public.review_account_sanction_appeal(uuid, text, text) to authenticated;
