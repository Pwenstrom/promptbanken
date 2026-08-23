-- Verifierar att admins läs-RPC:er är stängda för alla utom
-- plattformsägare (delprojekt 4).
--
-- Kör som en användare som INTE är plattformsägare: via PostgREST med den
-- användarens token, eller i SQL-editorn med rollen satt. Körs den som
-- postgres utan auth-kontext returnerar
-- app_private.current_user_is_platform_owner() också false, så testet är
-- meningsfullt även då — men den positiva vägen måste köras med en riktig
-- plattformsägar-JWT.

do $$
declare
    v_leaked boolean := false;
begin
    begin
        perform * from public.list_creator_submissions();
        v_leaked := true;
    exception when others then
        raise notice 'OK: list_creator_submissions avvisade icke-plattformsägare';
    end;

    if v_leaked then
        raise exception 'FEL: list_creator_submissions släppte igenom en icke-plattformsägare';
    end if;

    begin
        perform public.get_creator_submission('prompt', gen_random_uuid());
        v_leaked := true;
    exception when others then
        raise notice 'OK: get_creator_submission avvisade icke-plattformsägare';
    end;

    if v_leaked then
        raise exception 'FEL: get_creator_submission släppte igenom en icke-plattformsägare';
    end if;

    raise notice 'OK: läs-RPC:erna är stängda för icke-plattformsägare';
end;
$$;

-- Positiv väg, kör som plattformsägare. Ska returnera noll eller fler
-- rader utan fel:
--
--   select * from public.list_creator_submissions();
