create table public.market_listings (
    id uuid primary key default gen_random_uuid(),
    seller_id uuid not null references public.profiles(id) on delete cascade,
    source_private_id uuid,
    title text not null check (char_length(btrim(title)) between 1 and 120),
    description text not null default '' check (char_length(description) <= 3000),
    price bigint not null check (price between 1 and 1000000000),
    previous_price bigint check (previous_price is null or previous_price between 1 and 1000000000),
    currency text not null default 'KRW' check (currency = 'KRW'),
    brand_snapshot text not null default '' check (char_length(brand_snapshot) <= 120),
    category_snapshot text not null default '' check (char_length(category_snapshot) <= 80),
    size_snapshot text not null default '' check (char_length(size_snapshot) <= 80),
    color_hex_snapshot text not null default 'D9D9D9'
        check (color_hex_snapshot ~ '^[0-9A-Fa-f]{6}$'),
    condition text not null
        check (condition in ('like_new', 'excellent', 'good')),
    status text not null default 'active'
        check (status in ('active', 'reserved', 'sold', 'hidden', 'deleted')),
    meeting_name text check (meeting_name is null or char_length(meeting_name) <= 120),
    meeting_address text check (meeting_address is null or char_length(meeting_address) <= 300),
    meeting_latitude double precision
        check (meeting_latitude is null or meeting_latitude between -90 and 90),
    meeting_longitude double precision
        check (meeting_longitude is null or meeting_longitude between -180 and 180),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    check ((meeting_latitude is null) = (meeting_longitude is null)),
    check ((status = 'deleted' and deleted_at is not null) or status <> 'deleted')
);

create unique index market_listings_seller_source_private_id_key
on public.market_listings (seller_id, source_private_id)
where source_private_id is not null and deleted_at is null;

create index market_listings_feed_idx
on public.market_listings (created_at desc, id desc)
where status in ('active', 'reserved', 'sold') and deleted_at is null;

create index market_listings_seller_created_idx
on public.market_listings (seller_id, created_at desc);

create function public.capture_market_previous_price()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.price is distinct from old.price then
        new.previous_price = old.price;
    else
        new.previous_price = old.previous_price;
    end if;
    return new;
end;
$$;

revoke execute on function public.capture_market_previous_price() from public, anon, authenticated;

create trigger market_listings_capture_previous_price
before update on public.market_listings
for each row execute procedure public.capture_market_previous_price();

create trigger market_listings_set_updated_at
before update on public.market_listings
for each row execute procedure public.set_updated_at();

create table public.market_listing_media (
    id uuid primary key default gen_random_uuid(),
    listing_id uuid not null references public.market_listings(id) on delete cascade,
    storage_path text not null check (char_length(btrim(storage_path)) > 0),
    sort_order integer not null check (sort_order between 0 and 7),
    width integer check (width is null or width > 0),
    height integer check (height is null or height > 0),
    created_at timestamptz not null default now(),
    unique (listing_id, sort_order),
    unique (storage_path)
);

create index market_listing_media_listing_idx
on public.market_listing_media (listing_id, sort_order);

create table public.market_listing_verifications (
    listing_id uuid primary key references public.market_listings(id) on delete cascade,
    source_private_id uuid not null,
    garment_name_snapshot text not null check (char_length(btrim(garment_name_snapshot)) between 1 and 120),
    purchase_price bigint check (purchase_price is null or purchase_price between 0 and 1000000000),
    last_worn_at timestamptz,
    wear_count integer check (wear_count is null or wear_count >= 0),
    cutout_storage_path text,
    is_visible boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger market_listing_verifications_set_updated_at
before update on public.market_listing_verifications
for each row execute procedure public.set_updated_at();

create table public.market_listing_favorites (
    listing_id uuid not null references public.market_listings(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (listing_id, user_id)
);

create index market_listing_favorites_user_idx
on public.market_listing_favorites (user_id, created_at desc);

alter table public.market_listings enable row level security;
alter table public.market_listing_media enable row level security;
alter table public.market_listing_verifications enable row level security;
alter table public.market_listing_favorites enable row level security;

revoke all on table public.market_listings from anon, authenticated;
revoke all on table public.market_listing_media from anon, authenticated;
revoke all on table public.market_listing_verifications from anon, authenticated;
revoke all on table public.market_listing_favorites from anon, authenticated;

grant select, insert, update, delete on table public.market_listings to authenticated;
grant select, insert, update, delete on table public.market_listing_media to authenticated;
grant select, insert, update, delete on table public.market_listing_verifications to authenticated;
grant select, insert, delete on table public.market_listing_favorites to authenticated;

create policy "users can read visible market listings"
on public.market_listings for select
to authenticated
using (
    seller_id = (select auth.uid())
    or (
        status in ('active', 'reserved', 'sold')
        and deleted_at is null
    )
);

create policy "sellers can create their own market listings"
on public.market_listings for insert
to authenticated
with check (
    seller_id = (select auth.uid())
    and status = 'active'
    and deleted_at is null
);

create policy "sellers can update their own market listings"
on public.market_listings for update
to authenticated
using (seller_id = (select auth.uid()))
with check (seller_id = (select auth.uid()));

create policy "sellers can delete their own market listings"
on public.market_listings for delete
to authenticated
using (seller_id = (select auth.uid()));

create policy "users can read media on visible market listings"
on public.market_listing_media for select
to authenticated
using (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_media.listing_id
));

create policy "sellers can add media to their market listings"
on public.market_listing_media for insert
to authenticated
with check (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_media.listing_id
      and market_listings.seller_id = (select auth.uid())
));

create policy "sellers can update media on their market listings"
on public.market_listing_media for update
to authenticated
using (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_media.listing_id
      and market_listings.seller_id = (select auth.uid())
))
with check (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_media.listing_id
      and market_listings.seller_id = (select auth.uid())
));

create policy "sellers can delete media from their market listings"
on public.market_listing_media for delete
to authenticated
using (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_media.listing_id
      and market_listings.seller_id = (select auth.uid())
));

create policy "users can read visible market verifications"
on public.market_listing_verifications for select
to authenticated
using (
    is_visible
    or exists (
        select 1
        from public.market_listings
        where market_listings.id = market_listing_verifications.listing_id
          and market_listings.seller_id = (select auth.uid())
    )
);

create policy "sellers can create market verifications"
on public.market_listing_verifications for insert
to authenticated
with check (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_verifications.listing_id
      and market_listings.seller_id = (select auth.uid())
));

create policy "sellers can update market verifications"
on public.market_listing_verifications for update
to authenticated
using (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_verifications.listing_id
      and market_listings.seller_id = (select auth.uid())
))
with check (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_verifications.listing_id
      and market_listings.seller_id = (select auth.uid())
));

create policy "sellers can delete market verifications"
on public.market_listing_verifications for delete
to authenticated
using (exists (
    select 1
    from public.market_listings
    where market_listings.id = market_listing_verifications.listing_id
      and market_listings.seller_id = (select auth.uid())
));

create policy "users can read their own market favorites"
on public.market_listing_favorites for select
to authenticated
using (user_id = (select auth.uid()));

create policy "users can create their own market favorites"
on public.market_listing_favorites for insert
to authenticated
with check (
    user_id = (select auth.uid())
    and exists (
        select 1
        from public.market_listings
        where market_listings.id = market_listing_favorites.listing_id
    )
);

create policy "users can delete their own market favorites"
on public.market_listing_favorites for delete
to authenticated
using (user_id = (select auth.uid()));

do $$
declare
    table_name text;
begin
    foreach table_name in array array[
        'market_listings',
        'market_listing_media',
        'market_listing_verifications',
        'market_listing_favorites'
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
