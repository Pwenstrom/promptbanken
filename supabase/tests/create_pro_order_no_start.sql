-- Anropa create_pro_order med p_requested_plan='start' -> ska faila med
-- 'Delade arbetsytor skapas via create_shared_workspace()...'.
-- Pro och plus/enterprise ska fungera oförändrat.
--   select * from public.create_pro_order('start', 1, 'Test AB', null, null, null, 'a@b.se', 'Yta');
--     -> ERROR: Delade arbetsytor skapas via create_shared_workspace()...
select 'manuell kontroll' as note;
