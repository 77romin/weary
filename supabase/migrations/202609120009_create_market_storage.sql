insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'market-media',
    'market-media',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
)
on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "market media owners and visible listing viewers can read"
on storage.objects for select
to authenticated
using (
    bucket_id = 'market-media'
    and (
        owner_id = (select auth.uid()::text)
        or exists (
            select 1
            from public.market_listing_media
            join public.market_listings
              on market_listings.id = market_listing_media.listing_id
            where market_listing_media.storage_path = objects.name
              and market_listings.status in ('active', 'reserved', 'sold')
              and market_listings.deleted_at is null
        )
        or exists (
            select 1
            from public.market_listing_verifications
            join public.market_listings
              on market_listings.id = market_listing_verifications.listing_id
            where market_listing_verifications.cutout_storage_path = objects.name
              and market_listing_verifications.is_visible
              and market_listings.status in ('active', 'reserved', 'sold')
              and market_listings.deleted_at is null
        )
    )
);

create policy "market media owners can upload"
on storage.objects for insert
to authenticated
with check (
    bucket_id = 'market-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'heif', 'webp')
    and exists (
        select 1
        from public.market_listings
        where market_listings.id::text = (storage.foldername(name))[2]
          and market_listings.seller_id = (select auth.uid())
    )
);

create policy "market media owners can update"
on storage.objects for update
to authenticated
using (
    bucket_id = 'market-media'
    and owner_id = (select auth.uid()::text)
)
with check (
    bucket_id = 'market-media'
    and owner_id = (select auth.uid()::text)
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'heif', 'webp')
    and exists (
        select 1
        from public.market_listings
        where market_listings.id::text = (storage.foldername(name))[2]
          and market_listings.seller_id = (select auth.uid())
    )
);

create policy "market media owners can delete"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'market-media'
    and owner_id = (select auth.uid()::text)
    and (storage.foldername(name))[1] = (select auth.uid()::text)
);
