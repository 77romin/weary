alter table public.profiles
    add column nickname_key text;

with ranked_nicknames as (
    select
        id,
        lower(btrim(display_name)) as normalized_nickname,
        row_number() over (
            partition by lower(btrim(display_name))
            order by created_at, id
        ) as nickname_rank
    from public.profiles
    where handle_locked = true
)
update public.profiles as profile
set nickname_key = ranked.normalized_nickname
from ranked_nicknames as ranked
where profile.id = ranked.id
  and ranked.nickname_rank = 1;

create unique index profiles_nickname_key_unique
on public.profiles (nickname_key)
where nickname_key is not null;

create function public.set_profile_nickname_key()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.handle_locked then
        new.nickname_key := lower(btrim(new.display_name));
    else
        new.nickname_key := null;
    end if;
    return new;
end;
$$;

revoke execute on function public.set_profile_nickname_key()
from public, anon, authenticated;

create trigger profiles_set_nickname_key
before insert or update of display_name, handle_locked on public.profiles
for each row execute procedure public.set_profile_nickname_key();

create function public.check_account_availability(
    p_email text,
    p_handle text,
    p_nickname text
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'emailAvailable', not exists (
            select 1
            from auth.users
            where lower(email) = lower(btrim(p_email))
              and deleted_at is null
        ),
        'handleAvailable', not exists (
            select 1
            from public.profiles
            where lower(handle) = lower(btrim(p_handle))
        ),
        'nicknameAvailable', not exists (
            select 1
            from public.profiles
            where handle_locked = true
              and coalesce(nickname_key, lower(btrim(display_name))) = lower(btrim(p_nickname))
        )
    );
$$;

revoke all on function public.check_account_availability(text, text, text)
from public, anon, authenticated;
grant execute on function public.check_account_availability(text, text, text)
to service_role;

create function public.login_email_for_handle(p_handle text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select auth_user.email
    from public.profiles as profile
    join auth.users as auth_user on auth_user.id = profile.id
    where lower(profile.handle) = lower(btrim(p_handle))
      and auth_user.deleted_at is null
    limit 1;
$$;

revoke all on function public.login_email_for_handle(text)
from public, anon, authenticated;
grant execute on function public.login_email_for_handle(text)
to service_role;
