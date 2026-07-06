-- På en addon-yta: skapa mallar tills 200 finns, den 201:a ska faila:
--   'Den delade arbetsytan har nått gränsen på 200 mallar.'
-- Snabbtest: sänk tillfälligt max_prompts på addon-raden till 1 i staging,
-- skapa 1 mall (OK), försök en andra (faila), återställ sedan:
--   update public.shared_workspace_addons set max_prompts = 1 where workspace_id = '<addon-yta>';
--   ... skapa 1 prompt (OK), försök prompt 2 (faila) ...
--   update public.shared_workspace_addons set max_prompts = 200 where workspace_id = '<addon-yta>';
select 'manuell scenariokörning enligt kommentarer' as note;
