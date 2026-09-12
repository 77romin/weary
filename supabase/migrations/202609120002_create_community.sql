alter table public.profiles
    add column bio text not null default '',
    add column avatar_url text,
    add constraint profiles_bio_length check (char_length(bio) <= 300);

revoke all on table public.profiles from anon, authenticated;
grant select, update on table public.profiles to authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

revoke execute on function public.set_updated_at() from public, anon, authenticated;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute procedure public.set_updated_at();

create table public.posts (
    id uuid primary key default gen_random_uuid(),
    author_id uuid not null references public.profiles(id) on delete cascade,
    source_private_id uuid,
    caption text not null check (char_length(btrim(caption)) between 1 and 2000),
    tags text[] not null default '{}',
    visibility text not null default 'public'
        check (visibility in ('public', 'followers', 'private')),
    status text not null default 'active'
        check (status in ('active', 'hidden', 'deleted')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    check ((status = 'deleted' and deleted_at is not null) or status <> 'deleted')
);

create unique index posts_author_source_private_id_key
on public.posts (author_id, source_private_id)
where source_private_id is not null and deleted_at is null;
create index posts_feed_idx on public.posts (created_at desc)
where status = 'active' and deleted_at is null;
create index posts_author_created_idx on public.posts (author_id, created_at desc);
create index posts_tags_idx on public.posts using gin (tags);

create trigger posts_set_updated_at
before update on public.posts
for each row execute procedure public.set_updated_at();

create table public.post_media (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.posts(id) on delete cascade,
    storage_path text not null check (char_length(btrim(storage_path)) > 0),
    media_type text not null default 'image' check (media_type in ('image')),
    sort_order integer not null default 0 check (sort_order >= 0),
    width integer check (width is null or width > 0),
    height integer check (height is null or height > 0),
    created_at timestamptz not null default now(),
    unique (post_id, sort_order)
);

create index post_media_post_idx on public.post_media (post_id);

create table public.post_items (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.posts(id) on delete cascade,
    source_private_id uuid,
    name_snapshot text not null check (char_length(btrim(name_snapshot)) > 0),
    brand_snapshot text not null default '',
    category_snapshot text not null,
    size_snapshot text not null default '',
    color_hex_snapshot text not null default 'D9D9D9',
    image_storage_path text,
    sort_order integer not null default 0 check (sort_order >= 0),
    created_at timestamptz not null default now(),
    unique (post_id, sort_order)
);

create index post_items_post_idx on public.post_items (post_id);

create table public.comments (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.posts(id) on delete cascade,
    author_id uuid not null references public.profiles(id) on delete cascade,
    parent_comment_id uuid references public.comments(id) on delete cascade,
    body text not null check (char_length(btrim(body)) between 1 and 1000),
    status text not null default 'active' check (status in ('active', 'hidden', 'deleted')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    check ((status = 'deleted' and deleted_at is not null) or status <> 'deleted')
);

create index comments_post_created_idx on public.comments (post_id, created_at);
create index comments_author_idx on public.comments (author_id);
create index comments_parent_idx on public.comments (parent_comment_id)
where parent_comment_id is not null;

create function public.validate_comment_parent()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.parent_comment_id is not null and not exists (
        select 1
        from public.comments parent
        where parent.id = new.parent_comment_id
          and parent.post_id = new.post_id
    ) then
        raise exception 'parent comment must belong to the same post';
    end if;
    return new;
end;
$$;

revoke execute on function public.validate_comment_parent() from public, anon, authenticated;

create trigger comments_validate_parent
before insert or update of parent_comment_id, post_id on public.comments
for each row execute procedure public.validate_comment_parent();

create trigger comments_set_updated_at
before update on public.comments
for each row execute procedure public.set_updated_at();

create table public.post_likes (
    post_id uuid not null references public.posts(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, user_id)
);

create index post_likes_user_idx on public.post_likes (user_id, created_at desc);

create table public.bookmarks (
    post_id uuid not null references public.posts(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, user_id)
);

create index bookmarks_user_created_idx on public.bookmarks (user_id, created_at desc);

create table public.follows (
    follower_id uuid not null references public.profiles(id) on delete cascade,
    following_id uuid not null references public.profiles(id) on delete cascade,
    status text not null default 'accepted' check (status in ('pending', 'accepted')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (follower_id, following_id),
    check (follower_id <> following_id)
);

create index follows_following_idx on public.follows (following_id, created_at desc);

create trigger follows_set_updated_at
before update on public.follows
for each row execute procedure public.set_updated_at();

alter table public.posts enable row level security;
alter table public.post_media enable row level security;
alter table public.post_items enable row level security;
alter table public.comments enable row level security;
alter table public.post_likes enable row level security;
alter table public.bookmarks enable row level security;
alter table public.follows enable row level security;

revoke all on table public.posts from anon, authenticated;
revoke all on table public.post_media from anon, authenticated;
revoke all on table public.post_items from anon, authenticated;
revoke all on table public.comments from anon, authenticated;
revoke all on table public.post_likes from anon, authenticated;
revoke all on table public.bookmarks from anon, authenticated;
revoke all on table public.follows from anon, authenticated;

grant select, insert, update, delete on table public.posts to authenticated;
grant select, insert, update, delete on table public.post_media to authenticated;
grant select, insert, update, delete on table public.post_items to authenticated;
grant select, insert, update, delete on table public.comments to authenticated;
grant select, insert, delete on table public.post_likes to authenticated;
grant select, insert, delete on table public.bookmarks to authenticated;
grant select, insert, update, delete on table public.follows to authenticated;

create policy "users can read visible posts"
on public.posts for select
to authenticated
using (
    author_id = (select auth.uid())
    or (
        status = 'active'
        and deleted_at is null
        and (
            visibility = 'public'
            or (
                visibility = 'followers'
                and exists (
                    select 1
                    from public.follows
                    where follower_id = (select auth.uid())
                      and following_id = posts.author_id
                      and status = 'accepted'
                )
            )
        )
    )
);

create policy "users can create their own posts"
on public.posts for insert
to authenticated
with check (author_id = (select auth.uid()));

create policy "authors can update their own posts"
on public.posts for update
to authenticated
using (author_id = (select auth.uid()))
with check (author_id = (select auth.uid()));

create policy "authors can delete their own posts"
on public.posts for delete
to authenticated
using (author_id = (select auth.uid()));

create policy "users can read media on visible posts"
on public.post_media for select
to authenticated
using (exists (select 1 from public.posts where posts.id = post_media.post_id));

create policy "authors can add media to their posts"
on public.post_media for insert
to authenticated
with check (exists (
    select 1 from public.posts
    where posts.id = post_media.post_id
      and posts.author_id = (select auth.uid())
));

create policy "authors can update media on their posts"
on public.post_media for update
to authenticated
using (exists (
    select 1 from public.posts
    where posts.id = post_media.post_id
      and posts.author_id = (select auth.uid())
))
with check (exists (
    select 1 from public.posts
    where posts.id = post_media.post_id
      and posts.author_id = (select auth.uid())
));

create policy "authors can delete media on their posts"
on public.post_media for delete
to authenticated
using (exists (
    select 1 from public.posts
    where posts.id = post_media.post_id
      and posts.author_id = (select auth.uid())
));

create policy "users can read items on visible posts"
on public.post_items for select
to authenticated
using (exists (select 1 from public.posts where posts.id = post_items.post_id));

create policy "authors can add items to their posts"
on public.post_items for insert
to authenticated
with check (exists (
    select 1 from public.posts
    where posts.id = post_items.post_id
      and posts.author_id = (select auth.uid())
));

create policy "authors can update items on their posts"
on public.post_items for update
to authenticated
using (exists (
    select 1 from public.posts
    where posts.id = post_items.post_id
      and posts.author_id = (select auth.uid())
))
with check (exists (
    select 1 from public.posts
    where posts.id = post_items.post_id
      and posts.author_id = (select auth.uid())
));

create policy "authors can delete items on their posts"
on public.post_items for delete
to authenticated
using (exists (
    select 1 from public.posts
    where posts.id = post_items.post_id
      and posts.author_id = (select auth.uid())
));

create policy "users can read comments on visible posts"
on public.comments for select
to authenticated
using (
    (status = 'active' or author_id = (select auth.uid()))
    and exists (select 1 from public.posts where posts.id = comments.post_id)
);

create policy "users can comment on visible posts"
on public.comments for insert
to authenticated
with check (
    author_id = (select auth.uid())
    and status = 'active'
    and deleted_at is null
    and exists (
        select 1 from public.posts
        where posts.id = comments.post_id
          and posts.status = 'active'
          and posts.deleted_at is null
    )
);

create policy "authors can update their comments"
on public.comments for update
to authenticated
using (author_id = (select auth.uid()))
with check (author_id = (select auth.uid()));

create policy "authors can delete their comments"
on public.comments for delete
to authenticated
using (author_id = (select auth.uid()));

create policy "users can read likes on visible posts"
on public.post_likes for select
to authenticated
using (exists (select 1 from public.posts where posts.id = post_likes.post_id));

create policy "users can like visible posts"
on public.post_likes for insert
to authenticated
with check (
    user_id = (select auth.uid())
    and exists (
        select 1 from public.posts
        where posts.id = post_likes.post_id
          and posts.status = 'active'
          and posts.deleted_at is null
    )
);

create policy "users can remove their own likes"
on public.post_likes for delete
to authenticated
using (user_id = (select auth.uid()));

create policy "users can read their own bookmarks"
on public.bookmarks for select
to authenticated
using (user_id = (select auth.uid()));

create policy "users can bookmark visible posts"
on public.bookmarks for insert
to authenticated
with check (
    user_id = (select auth.uid())
    and exists (
        select 1 from public.posts
        where posts.id = bookmarks.post_id
          and posts.status = 'active'
          and posts.deleted_at is null
    )
);

create policy "users can remove their own bookmarks"
on public.bookmarks for delete
to authenticated
using (user_id = (select auth.uid()));

create policy "users can read follow relationships"
on public.follows for select
to authenticated
using (true);

create policy "users can create their own follows"
on public.follows for insert
to authenticated
with check (follower_id = (select auth.uid()));

create policy "followers can update their relationships"
on public.follows for update
to authenticated
using (follower_id = (select auth.uid()))
with check (follower_id = (select auth.uid()));

create policy "followers can delete their relationships"
on public.follows for delete
to authenticated
using (follower_id = (select auth.uid()));
