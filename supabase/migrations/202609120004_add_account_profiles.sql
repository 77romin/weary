alter table public.profiles
    add column if not exists handle_locked boolean not null default false,
    add column if not exists height_cm numeric(5,1),
    add column if not exists weight_kg numeric(5,1),
    add column if not exists gender text,
    add column if not exists chest_cm numeric(5,1),
    add column if not exists waist_cm numeric(5,1),
    add column if not exists hip_cm numeric(5,1),
    add column if not exists inseam_cm numeric(5,1);

alter table public.profiles
    add constraint profiles_handle_format_check
        check (handle is null or handle ~ '^[a-z0-9._]{3,20}$'),
    add constraint profiles_height_check check (height_cm is null or height_cm between 80 and 250),
    add constraint profiles_weight_check check (weight_kg is null or weight_kg between 20 and 400),
    add constraint profiles_gender_check check (gender is null or gender in ('female', 'male', 'nonbinary')),
    add constraint profiles_chest_check check (chest_cm is null or chest_cm between 30 and 250),
    add constraint profiles_waist_check check (waist_cm is null or waist_cm between 30 and 250),
    add constraint profiles_hip_check check (hip_cm is null or hip_cm between 30 and 250),
    add constraint profiles_inseam_check check (inseam_cm is null or inseam_cm between 20 and 150);

create unique index if not exists profiles_handle_lower_key
on public.profiles (lower(handle))
where handle is not null;

update public.profiles
set handle_locked = true
where handle is not null;

create or replace function public.lock_profile_handle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if old.handle_locked and new.handle is distinct from old.handle then
        raise exception 'WEARy ID cannot be changed after it is set';
    end if;

    if old.handle is null and new.handle is not null then
        new.handle := lower(trim(new.handle));
        new.handle_locked := true;
    end if;

    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists lock_profile_handle_before_update on public.profiles;
create trigger lock_profile_handle_before_update
before update on public.profiles
for each row execute procedure public.lock_profile_handle();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
    requested_handle text;
begin
    requested_handle := lower(nullif(trim(new.raw_user_meta_data ->> 'handle'), ''));

    insert into public.profiles (
        id,
        display_name,
        handle,
        handle_locked,
        avatar_initials
    )
    values (
        new.id,
        coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 'WEARy 사용자'),
        requested_handle,
        requested_handle is not null,
        coalesce(nullif(trim(new.raw_user_meta_data ->> 'avatar_initials'), ''), 'WY')
    );
    return new;
end;
$$;
