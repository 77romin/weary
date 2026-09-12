create table public.market_conversations (
    id uuid primary key default gen_random_uuid(),
    listing_id uuid not null references public.market_listings(id) on delete cascade,
    buyer_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    last_message_at timestamptz,
    unique (listing_id, buyer_id)
);

create index market_conversations_listing_activity_idx
on public.market_conversations (listing_id, last_message_at desc nulls last, created_at desc);

create index market_conversations_buyer_activity_idx
on public.market_conversations (buyer_id, last_message_at desc nulls last, created_at desc);

create trigger market_conversations_set_updated_at
before update on public.market_conversations
for each row execute procedure public.set_updated_at();

create table public.market_messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references public.market_conversations(id) on delete cascade,
    sender_id uuid not null references public.profiles(id) on delete cascade,
    body text not null check (char_length(btrim(body)) between 1 and 2000),
    created_at timestamptz not null default now()
);

create index market_messages_conversation_created_idx
on public.market_messages (conversation_id, created_at, id);

alter table public.market_conversations enable row level security;
alter table public.market_messages enable row level security;

revoke all on table public.market_conversations from anon, authenticated;
revoke all on table public.market_messages from anon, authenticated;
grant select, insert on table public.market_conversations to authenticated;
grant select, insert on table public.market_messages to authenticated;

create policy "participants can read market conversations"
on public.market_conversations for select
to authenticated
using (
    buyer_id = (select auth.uid())
    or exists (
        select 1 from public.market_listings
        where market_listings.id = market_conversations.listing_id
          and market_listings.seller_id = (select auth.uid())
    )
);

create policy "buyers can start market conversations"
on public.market_conversations for insert
to authenticated
with check (
    buyer_id = (select auth.uid())
    and exists (
        select 1 from public.market_listings
        where market_listings.id = market_conversations.listing_id
          and market_listings.seller_id <> (select auth.uid())
          and market_listings.status in ('active', 'reserved', 'sold')
          and market_listings.deleted_at is null
    )
);

create policy "participants can read market messages"
on public.market_messages for select
to authenticated
using (exists (
    select 1
    from public.market_conversations
    join public.market_listings
      on market_listings.id = market_conversations.listing_id
    where market_conversations.id = market_messages.conversation_id
      and (
          market_conversations.buyer_id = (select auth.uid())
          or market_listings.seller_id = (select auth.uid())
      )
));

create policy "participants can send market messages"
on public.market_messages for insert
to authenticated
with check (
    sender_id = (select auth.uid())
    and exists (
        select 1
        from public.market_conversations
        join public.market_listings
          on market_listings.id = market_conversations.listing_id
        where market_conversations.id = market_messages.conversation_id
          and (
              market_conversations.buyer_id = (select auth.uid())
              or market_listings.seller_id = (select auth.uid())
          )
    )
);

create function public.get_or_create_market_conversation(p_listing_id uuid)
returns public.market_conversations
language plpgsql
set search_path = ''
as $$
declare
    result public.market_conversations;
begin
    select * into result
    from public.market_conversations
    where listing_id = p_listing_id
      and buyer_id = auth.uid();

    if result.id is not null then
        return result;
    end if;

    insert into public.market_conversations (listing_id, buyer_id)
    values (p_listing_id, auth.uid())
    on conflict (listing_id, buyer_id) do nothing
    returning * into result;

    if result.id is null then
        select * into result
        from public.market_conversations
        where listing_id = p_listing_id
          and buyer_id = auth.uid();
    end if;

    if result.id is null then
        raise insufficient_privilege using message = 'visible listing buyer required';
    end if;

    return result;
end;
$$;

revoke all on function public.get_or_create_market_conversation(uuid) from public, anon;
grant execute on function public.get_or_create_market_conversation(uuid) to authenticated;

create function public.touch_market_conversation_from_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.market_conversations
    set last_message_at = new.created_at
    where id = new.conversation_id;
    return new;
end;
$$;

revoke execute on function public.touch_market_conversation_from_message()
from public, anon, authenticated;

create trigger market_messages_touch_conversation
after insert on public.market_messages
for each row execute procedure public.touch_market_conversation_from_message();

do $$
declare
    table_name text;
begin
    foreach table_name in array array[
        'market_conversations',
        'market_messages'
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
