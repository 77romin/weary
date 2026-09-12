drop policy "sellers can create their own market listings"
on public.market_listings;

create policy "sellers can create their own market listings"
on public.market_listings for insert
to authenticated
with check (
    seller_id = (select auth.uid())
    and status in ('active', 'hidden')
    and deleted_at is null
);

drop policy "sellers can add media to their market listings"
on public.market_listing_media;
drop policy "sellers can update media on their market listings"
on public.market_listing_media;

create policy "sellers can add media to their market listings"
on public.market_listing_media for insert
to authenticated
with check (
    storage_path like (select auth.uid()::text) || '/' || listing_id::text || '/%'
    and exists (
        select 1 from public.market_listings
        where market_listings.id = market_listing_media.listing_id
          and market_listings.seller_id = (select auth.uid())
    )
);

create policy "sellers can update media on their market listings"
on public.market_listing_media for update
to authenticated
using (exists (
    select 1 from public.market_listings
    where market_listings.id = market_listing_media.listing_id
      and market_listings.seller_id = (select auth.uid())
))
with check (
    storage_path like (select auth.uid()::text) || '/' || listing_id::text || '/%'
    and exists (
        select 1 from public.market_listings
        where market_listings.id = market_listing_media.listing_id
          and market_listings.seller_id = (select auth.uid())
    )
);

drop policy "sellers can create market verifications"
on public.market_listing_verifications;
drop policy "sellers can update market verifications"
on public.market_listing_verifications;

create policy "sellers can create market verifications"
on public.market_listing_verifications for insert
to authenticated
with check (
    (cutout_storage_path is null or cutout_storage_path like (select auth.uid()::text) || '/' || listing_id::text || '/%')
    and exists (
        select 1 from public.market_listings
        where market_listings.id = market_listing_verifications.listing_id
          and market_listings.seller_id = (select auth.uid())
    )
);

create policy "sellers can update market verifications"
on public.market_listing_verifications for update
to authenticated
using (exists (
    select 1 from public.market_listings
    where market_listings.id = market_listing_verifications.listing_id
      and market_listings.seller_id = (select auth.uid())
))
with check (
    (cutout_storage_path is null or cutout_storage_path like (select auth.uid()::text) || '/' || listing_id::text || '/%')
    and exists (
        select 1 from public.market_listings
        where market_listings.id = market_listing_verifications.listing_id
          and market_listings.seller_id = (select auth.uid())
    )
);

create function public.replace_market_listing(
    p_listing_id uuid,
    p_title text,
    p_description text,
    p_price bigint,
    p_condition text,
    p_status text,
    p_meeting_name text,
    p_meeting_address text,
    p_meeting_latitude double precision,
    p_meeting_longitude double precision,
    p_media jsonb,
    p_verification jsonb
)
returns public.market_listings
language plpgsql
set search_path = ''
as $$
declare
    updated_listing public.market_listings;
    media_item jsonb;
begin
    if jsonb_array_length(coalesce(p_media, '[]'::jsonb)) > 8 then
        raise exception 'a listing supports at most 8 images';
    end if;

    update public.market_listings
    set title = p_title,
        description = p_description,
        price = p_price,
        condition = p_condition,
        status = p_status,
        meeting_name = nullif(btrim(p_meeting_name), ''),
        meeting_address = nullif(btrim(p_meeting_address), ''),
        meeting_latitude = p_meeting_latitude,
        meeting_longitude = p_meeting_longitude
    where id = p_listing_id
      and seller_id = auth.uid()
    returning * into updated_listing;

    if updated_listing.id is null then
        raise insufficient_privilege using message = 'listing owner required';
    end if;

    delete from public.market_listing_media where listing_id = p_listing_id;
    for media_item in select value from jsonb_array_elements(coalesce(p_media, '[]'::jsonb))
    loop
        insert into public.market_listing_media (listing_id, storage_path, sort_order)
        values (p_listing_id, media_item->>'storage_path', (media_item->>'sort_order')::integer);
    end loop;

    delete from public.market_listing_verifications where listing_id = p_listing_id;
    if p_verification is not null and jsonb_typeof(p_verification) <> 'null' then
        insert into public.market_listing_verifications (
            listing_id, source_private_id, garment_name_snapshot, purchase_price,
            last_worn_at, wear_count, cutout_storage_path, is_visible
        ) values (
            p_listing_id,
            (p_verification->>'source_private_id')::uuid,
            p_verification->>'garment_name_snapshot',
            nullif(p_verification->>'purchase_price', '')::bigint,
            nullif(p_verification->>'last_worn_at', '')::timestamptz,
            nullif(p_verification->>'wear_count', '')::integer,
            nullif(p_verification->>'cutout_storage_path', ''),
            coalesce((p_verification->>'is_visible')::boolean, false)
        );
    end if;

    return updated_listing;
end;
$$;

revoke all on function public.replace_market_listing(
    uuid, text, text, bigint, text, text, text, text,
    double precision, double precision, jsonb, jsonb
) from public, anon;
grant execute on function public.replace_market_listing(
    uuid, text, text, bigint, text, text, text, text,
    double precision, double precision, jsonb, jsonb
) to authenticated;
