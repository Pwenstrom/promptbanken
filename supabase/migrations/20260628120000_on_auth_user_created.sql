-- Auto-provision a personal workspace when a new user signs up.
-- Wraps ensure_personal_workspace() which is idempotent and security definer.

create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.ensure_personal_workspace();
    return new;
exception when others then
    -- Log but never block sign-up if workspace creation fails.
    raise warning 'handle_new_user: could not create workspace for user %: %', new.id, sqlerrm;
    return new;
end;
$$;

revoke all on function app_private.handle_new_user() from public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function app_private.handle_new_user();
