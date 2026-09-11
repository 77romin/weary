create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null default 'WEARy 사용자',
    handle text unique,
    avatar_initials text not null default 'WY',
    accent_hex text not null default 'C7F25B',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are readable by signed-in users"
on public.profiles
for select
to authenticated
using (true);

create policy "users can update their own profile"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
    insert into public.profiles (id, display_name, handle, avatar_initials)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'display_name', 'WEARy 사용자'),
        'weary_' || left(replace(new.id::text, '-', ''), 8),
        coalesce(new.raw_user_meta_data ->> 'avatar_initials', 'WY')
    );
    return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
