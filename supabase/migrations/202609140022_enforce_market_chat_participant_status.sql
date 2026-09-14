create function public.get_market_chat_write_status(
    p_listing_id uuid,
    p_conversation_id uuid default null
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    buyer_user_id uuid;
    seller_user_id uuid;
    counterpart_user_id uuid;
begin
    if current_user_id is null then
        return 'not_authenticated';
    end if;

    select listing.seller_id into seller_user_id
    from public.market_listings as listing
    where listing.id = p_listing_id
      and listing.deleted_at is null;

    if seller_user_id is null then
        return 'not_participant';
    end if;

    if p_conversation_id is not null then
        select conversation.buyer_id into buyer_user_id
        from public.market_conversations as conversation
        where conversation.id = p_conversation_id
          and conversation.listing_id = p_listing_id;
    elsif current_user_id <> seller_user_id then
        buyer_user_id := current_user_id;
    end if;

    if current_user_id = seller_user_id and buyer_user_id is not null then
        counterpart_user_id := buyer_user_id;
    elsif current_user_id = buyer_user_id then
        counterpart_user_id := seller_user_id;
    else
        return 'not_participant';
    end if;

    if exists (
        select 1 from public.account_sanctions
        where user_id = current_user_id
          and kind in ('restriction', 'suspension')
          and starts_at <= now()
          and lifted_at is null
          and (ends_at is null or ends_at > now())
    ) then
        return 'self_sanctioned';
    end if;

    if exists (
        select 1 from public.account_sanctions
        where user_id = counterpart_user_id
          and kind in ('restriction', 'suspension')
          and starts_at <= now()
          and lifted_at is null
          and (ends_at is null or ends_at > now())
    ) then
        return 'counterpart_sanctioned';
    end if;

    if exists (
        select 1 from public.user_blocks
        where blocker_id = current_user_id
          and blocked_id = counterpart_user_id
    ) then
        return 'blocked_by_self';
    end if;

    if exists (
        select 1 from public.user_blocks
        where blocker_id = counterpart_user_id
          and blocked_id = current_user_id
    ) then
        return 'blocked_by_counterpart';
    end if;

    return 'allowed';
end;
$$;

revoke all on function public.get_market_chat_write_status(uuid, uuid) from public, anon;
grant execute on function public.get_market_chat_write_status(uuid, uuid) to authenticated;

create function public.enforce_market_conversation_participant_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    seller_user_id uuid;
begin
    select seller_id into seller_user_id
    from public.market_listings
    where id = new.listing_id
      and deleted_at is null;

    if exists (
        select 1 from public.user_blocks
        where (blocker_id = new.buyer_id and blocked_id = seller_user_id)
           or (blocker_id = seller_user_id and blocked_id = new.buyer_id)
    ) then
        raise exception '차단된 사용자와는 거래 대화를 시작할 수 없어요.'
            using errcode = '42501';
    end if;

    if exists (
        select 1 from public.account_sanctions
        where user_id = seller_user_id
          and kind in ('restriction', 'suspension')
          and starts_at <= now()
          and lifted_at is null
          and (ends_at is null or ends_at > now())
    ) then
        raise exception '정책 위반으로 제한된 사용자와는 거래 대화를 시작할 수 없어요.'
            using errcode = '42501';
    end if;

    return new;
end;
$$;

revoke all on function public.enforce_market_conversation_participant_status()
from public, anon, authenticated;

create trigger market_conversations_enforce_participant_status
before insert on public.market_conversations
for each row execute procedure public.enforce_market_conversation_participant_status();

create function public.enforce_market_message_participant_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    listing_id uuid;
    write_status text;
begin
    select conversation.listing_id into listing_id
    from public.market_conversations as conversation
    where conversation.id = new.conversation_id;

    write_status := public.get_market_chat_write_status(listing_id, new.conversation_id);

    case write_status
        when 'allowed' then
            return new;
        when 'self_sanctioned' then
            raise exception '정책 위반으로 채팅 이용이 제한됐어요.' using errcode = '42501';
        when 'counterpart_sanctioned' then
            raise exception '정책 위반으로 제한된 사용자에게는 메시지를 보낼 수 없어요.' using errcode = '42501';
        when 'blocked_by_self' then
            raise exception '차단한 사용자에게는 메시지를 보낼 수 없어요.' using errcode = '42501';
        when 'blocked_by_counterpart' then
            raise exception '이 사용자와는 메시지를 주고받을 수 없어요.' using errcode = '42501';
        else
            raise exception '거래 대화 참여자만 메시지를 보낼 수 있어요.' using errcode = '42501';
    end case;
end;
$$;

revoke all on function public.enforce_market_message_participant_status()
from public, anon, authenticated;

create trigger market_messages_enforce_participant_status
before insert on public.market_messages
for each row execute procedure public.enforce_market_message_participant_status();
