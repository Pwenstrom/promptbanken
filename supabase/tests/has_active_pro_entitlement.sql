-- Kräver en känd Pro-användare och en känd Free-användare i staging.
-- Ersätt UUID:erna nedan med riktiga staging-user_id.
select app_private.has_active_pro_entitlement('<PRO_USER_UUID>');   -- Expected: t
select app_private.has_active_pro_entitlement('<FREE_USER_UUID>');  -- Expected: f
