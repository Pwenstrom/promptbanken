-- Verifiera att de statiska parametriserade prompterna är publicerade i
-- katalogen och att katalogpaketen pekar på samma promptposter.

do $$
declare
    expected_prompt_count constant integer := 10;
    actual_prompt_count integer;
    actual_variant_count integer;
    actual_package_link_count integer;
begin
    with expected_prompts(slug) as (
        values
            ('klarsprak'),
            ('mejl'),
            ('faq'),
            ('kallelse'),
            ('beslutsunderlag'),
            ('rutin'),
            ('tvaversioner'),
            ('informationsutskick'),
            ('enkel_infografik'),
            ('illustration_informationsutskick')
    )
    select count(*)
    into actual_prompt_count
    from expected_prompts expected
    join public.catalog_prompts prompt
      on prompt.slug = expected.slug
     and prompt.status = 'published';

    if actual_prompt_count <> expected_prompt_count then
        raise exception
            'Förväntade % publicerade parametriserade katalogprompter, hittade %',
            expected_prompt_count,
            actual_prompt_count;
    end if;

    with expected_prompts(slug) as (
        values
            ('klarsprak'),
            ('mejl'),
            ('faq'),
            ('kallelse'),
            ('beslutsunderlag'),
            ('rutin'),
            ('tvaversioner'),
            ('informationsutskick'),
            ('enkel_infografik'),
            ('illustration_informationsutskick')
    )
    select count(*)
    into actual_variant_count
    from expected_prompts expected
    join public.catalog_prompts prompt on prompt.slug = expected.slug
    join public.catalog_prompt_variants variant
      on variant.prompt_id = prompt.id
     and variant.context_key = 'generell'
    where length(variant.prompt_text) > 0
      and jsonb_typeof(variant.parameter_schema) = 'object'
      and jsonb_array_length(variant.parameter_schema -> 'fields') between 3 and 4
      and (
          variant.prompt_text like '%{{%'
          or variant.parameter_schema ? 'legacy_fallback_field'
      )
      and jsonb_typeof(variant.default_bindings) = 'object'
      and jsonb_typeof(variant.binding_overrides) = 'array';

    if actual_variant_count <> expected_prompt_count then
        raise exception
            'Förväntade % kompletta parametriserade katalogvarianter, hittade %',
            expected_prompt_count,
            actual_variant_count;
    end if;

    with expected_links(package_slug, prompt_slug) as (
        values
            ('kommunikation', 'klarsprak'),
            ('kommunikation', 'mejl'),
            ('kommunikation', 'faq'),
            ('kommunikation', 'kallelse'),
            ('beslutsberedning', 'beslutsunderlag'),
            ('processer', 'rutin'),
            ('kommunikation', 'tvaversioner'),
            ('kommunikation', 'informationsutskick'),
            ('visuellt', 'enkel_infografik'),
            ('visuellt', 'illustration_informationsutskick')
    )
    select count(*)
    into actual_package_link_count
    from expected_links expected
    join public.catalog_packages package on package.slug = expected.package_slug
    join public.catalog_prompts prompt on prompt.slug = expected.prompt_slug
    join public.catalog_package_items item
      on item.package_id = package.id
     and item.prompt_id = prompt.id;

    if actual_package_link_count <> expected_prompt_count then
        raise exception
            'Förväntade % paketkopplingar för parametriserade prompter, hittade %',
            expected_prompt_count,
            actual_package_link_count;
    end if;
end
$$;
