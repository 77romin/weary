create table public.profile_measurements (
    id uuid primary key references auth.users(id) on delete cascade,
    height_cm numeric(5,1) check (height_cm is null or height_cm between 80 and 250),
    weight_kg numeric(5,1) check (weight_kg is null or weight_kg between 20 and 400),
    gender text check (gender is null or gender in ('female', 'male', 'nonbinary')),
    chest_cm numeric(5,1) check (chest_cm is null or chest_cm between 30 and 250),
    waist_cm numeric(5,1) check (waist_cm is null or waist_cm between 30 and 250),
    hip_cm numeric(5,1) check (hip_cm is null or hip_cm between 30 and 250),
    inseam_cm numeric(5,1) check (inseam_cm is null or inseam_cm between 20 and 150),
    updated_at timestamptz not null default now()
);

insert into public.profile_measurements (
    id, height_cm, weight_kg, gender, chest_cm, waist_cm, hip_cm, inseam_cm
)
select id, height_cm, weight_kg, gender, chest_cm, waist_cm, hip_cm, inseam_cm
from public.profiles
where height_cm is not null
   or weight_kg is not null
   or gender is not null
   or chest_cm is not null
   or waist_cm is not null
   or hip_cm is not null
   or inseam_cm is not null;

alter table public.profiles
    drop column height_cm,
    drop column weight_kg,
    drop column gender,
    drop column chest_cm,
    drop column waist_cm,
    drop column hip_cm,
    drop column inseam_cm;

alter table public.profile_measurements enable row level security;

create policy "users can read their own measurements"
on public.profile_measurements
for select
to authenticated
using ((select auth.uid()) = id);

create policy "users can insert their own measurements"
on public.profile_measurements
for insert
to authenticated
with check ((select auth.uid()) = id);

create policy "users can update their own measurements"
on public.profile_measurements
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy "users can delete their own measurements"
on public.profile_measurements
for delete
to authenticated
using ((select auth.uid()) = id);

grant select, insert, update, delete on public.profile_measurements to authenticated;

create or replace function public.lock_profile_handle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if old.handle is not null and new.handle is distinct from old.handle then
        raise exception 'WEARy ID cannot be changed after it is set';
    end if;

    if old.handle is null and new.handle is not null then
        new.handle := lower(trim(new.handle));
    end if;

    new.handle_locked := old.handle_locked or new.handle is not null;
    new.updated_at := now();
    return new;
end;
$$;
