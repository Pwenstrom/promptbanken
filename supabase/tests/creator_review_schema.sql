-- Verifierar schemat för det redaktionella granskningsflödet (delprojekt 4).
-- Kör mot staging eller länkad produktion efter
-- 20260823090000_creator_review_schema.sql.

do $$
declare
    v_missing text;
begin
    select string_agg(expected.col, ', ')
      into v_missing
      from (values
            ('content_items', 'creator_consent_distribution'),
            ('content_items', 'creator_rights_attested'),
            ('creator_package_drafts', 'creator_consent_distribution'),
            ('creator_package_drafts', 'creator_rights_attested'),
            ('creator_package_drafts', 'review_note'),
            ('catalog_prompts', 'creator_profile_id'),
            ('catalog_prompts', 'creator_consent_distribution'),
            ('catalog_prompts', 'creator_rights_attested'),
            ('catalog_packages', 'creator_profile_id'),
            ('catalog_packages', 'creator_consent_distribution'),
            ('catalog_packages', 'creator_rights_attested')
           ) as expected(tbl, col)
     where not exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public'
            and c.table_name = expected.tbl
            and c.column_name = expected.col
     );

    if v_missing is not null then
        raise exception 'FEL: dessa kolumner saknas: %', v_missing;
    end if;

    if not exists (
        select 1 from pg_tables
         where schemaname = 'public' and tablename = 'creator_submission_screenings'
    ) then
        raise exception 'FEL: creator_submission_screenings saknas';
    end if;

    if not exists (
        select 1 from pg_tables
         where schemaname = 'public'
           and tablename = 'creator_submission_screenings'
           and rowsecurity = true
    ) then
        raise exception 'FEL: RLS är inte påslaget på creator_submission_screenings';
    end if;

    -- Granskningstabellen ska inte vara läsbar för vanliga klienter.
    -- Ingen policy finns, men en tabellbred grant skulle ändå släppa
    -- igenom PostgREST-frågor.
    if exists (
        select 1 from information_schema.role_table_grants
         where table_schema = 'public'
           and table_name = 'creator_submission_screenings'
           and grantee in ('anon', 'authenticated')
    ) then
        raise exception 'FEL: creator_submission_screenings har grants till anon/authenticated';
    end if;

    -- Paket-tabellerna från delprojekt 3 ärvde samma breda grants och
    -- städades i 20260823090500_creator_review_grant_hardening.sql. RLS
    -- blockerade skrivningarna redan, men två lager är poängen.
    if exists (
        select 1 from information_schema.role_table_grants
         where table_schema = 'public'
           and table_name in ('creator_package_drafts', 'creator_package_items')
           and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
           and grantee in ('anon', 'authenticated')
    ) then
        raise exception 'FEL: paket-tabellerna har skrivgrants till anon/authenticated';
    end if;

    raise notice 'OK: schemat för granskningsflödet är på plats';
end;
$$;
