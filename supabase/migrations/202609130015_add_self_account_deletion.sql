create function public.delete_current_user()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
begin
    if current_user_id is null then
        raise insufficient_privilege using message = 'authentication required';
    end if;

    delete from auth.users where id = current_user_id;
    if not found then
        raise no_data_found using message = 'current user not found';
    end if;
end;
$$;

revoke all on function public.delete_current_user() from public, anon;
grant execute on function public.delete_current_user() to authenticated;
