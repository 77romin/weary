drop policy "users can read visible market verifications"
on public.market_listing_verifications;

create policy "users can read visible market verifications"
on public.market_listing_verifications for select
to authenticated
using (
    exists (
        select 1
        from public.market_listings
        where market_listings.id = market_listing_verifications.listing_id
          and market_listings.seller_id = (select auth.uid())
    )
    or (
        is_visible
        and exists (
            select 1
            from public.market_listings
            where market_listings.id = market_listing_verifications.listing_id
              and market_listings.status in ('active', 'reserved', 'sold')
              and market_listings.deleted_at is null
        )
    )
);
