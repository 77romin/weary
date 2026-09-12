insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'community-media',
    'community-media',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
)
on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "community media owners and viewers can read"
on storage.objects for select
to authenticated
using (
    bucket_id = 'community-media'
    and (
        owner_id = (select auth.uid()::text)
        or exists (
            select 1
            from public.post_media
            where post_media.storage_path = objects.name
        )
        or exists (
            select 1
            from public.post_items
            where post_items.image_storage_path = objects.name
        )
    )
);

create policy "community media owners can upload"
on storage.objects for insert
to authenticated
with check (
    bucket_id = 'community-media'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'heif', 'webp')
    and exists (
        select 1
        from public.posts
        where posts.id::text = (storage.foldername(name))[2]
          and posts.author_id = (select auth.uid())
    )
);

create policy "community media owners can update"
on storage.objects for update
to authenticated
using (
    bucket_id = 'community-media'
    and owner_id = (select auth.uid()::text)
)
with check (
    bucket_id = 'community-media'
    and owner_id = (select auth.uid()::text)
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'heif', 'webp')
    and exists (
        select 1
        from public.posts
        where posts.id::text = (storage.foldername(name))[2]
          and posts.author_id = (select auth.uid())
    )
);

create policy "community media owners can delete"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'community-media'
    and owner_id = (select auth.uid()::text)
    and (storage.foldername(name))[1] = (select auth.uid()::text)
);
