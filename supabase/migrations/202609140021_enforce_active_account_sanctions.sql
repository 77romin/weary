create function public.can_current_user_write_shared_content()
returns boolean
language sql stable security definer set search_path = '' as $$
    select not exists (
        select 1 from public.account_sanctions
        where user_id = (select auth.uid())
          and kind in ('restriction', 'suspension')
          and starts_at <= now()
          and lifted_at is null
          and (ends_at is null or ends_at > now())
    );
$$;

revoke all on function public.can_current_user_write_shared_content() from public, anon;
grant execute on function public.can_current_user_write_shared_content() to authenticated;

create function public.enforce_shared_content_write_access()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if not public.can_current_user_write_shared_content() then
        raise exception '계정 이용 제한 중에는 커뮤니티와 마켓 활동을 할 수 없어요.'
            using errcode = '42501', hint = 'MY의 계정 제재·이의 제기에서 상태를 확인해 주세요.';
    end if;
    return new;
end;
$$;

revoke all on function public.enforce_shared_content_write_access() from public, anon, authenticated;

do $$
declare table_name text;
begin
    foreach table_name in array array[
        'posts', 'post_media', 'post_items', 'comments', 'post_likes', 'bookmarks', 'follows',
        'market_listings', 'market_listing_media', 'market_listing_verifications',
        'market_listing_favorites', 'market_conversations', 'market_messages'
    ] loop
        execute format(
            'create trigger %I before insert or update on public.%I for each row execute procedure public.enforce_shared_content_write_access()',
            table_name || '_enforce_account_sanction', table_name
        );
    end loop;
end;
$$;

create policy "restricted accounts cannot upload community media"
on storage.objects as restrictive for insert to authenticated
with check (
    bucket_id <> 'community-media'
    or (select public.can_current_user_write_shared_content())
);

create policy "restricted accounts cannot update community media"
on storage.objects as restrictive for update to authenticated
using (
    bucket_id <> 'community-media'
    or (select public.can_current_user_write_shared_content())
)
with check (
    bucket_id <> 'community-media'
    or (select public.can_current_user_write_shared_content())
);

create policy "restricted accounts cannot upload market media"
on storage.objects as restrictive for insert to authenticated
with check (
    bucket_id <> 'market-media'
    or (select public.can_current_user_write_shared_content())
);

create policy "restricted accounts cannot update market media"
on storage.objects as restrictive for update to authenticated
using (
    bucket_id <> 'market-media'
    or (select public.can_current_user_write_shared_content())
)
with check (
    bucket_id <> 'market-media'
    or (select public.can_current_user_write_shared_content())
);
