-- Publik wrapper för rollkollen, så att frontend kan fråga om sin egen roll.
--
-- app_private.current_user_is_platform_owner() finns sedan RLS-migrationen,
-- men app_private är inte anropbart via PostgREST. Utan den här wrappern kan
-- inloggningen inte veta vart användaren ska skickas, och alla hamnar på
-- admin.html — creators inkluderade, som då får plattformsägarens hela
-- sidomeny och ett "Ingen åtkomst" i innehållsytan.
--
-- Funktionen svarar bara om den anropande användaren själv. Den tar inga
-- argument och kan inte fråga om någon annan.

create or replace function public.am_i_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select app_private.current_user_is_platform_owner();
$$;

-- Databasens default-privilegier ger nya funktioner i public till både anon
-- och authenticated. "revoke från public" rör inte de rollspecifika
-- grantsen, så anon måste plockas bort uttryckligen.
revoke all on function public.am_i_platform_owner() from public;
revoke all on function public.am_i_platform_owner() from anon;
grant execute on function public.am_i_platform_owner() to authenticated;

comment on function public.am_i_platform_owner() is
    'Säger om den inloggade användaren är plattformsägare. Används för att '
    'routa efter inloggning; svarar aldrig om någon annan användare.';
