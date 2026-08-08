-- ============================================================
-- CARGA MANUAL DE HOJAS DE CONTROL DESDE LA APP
-- Correr en el SQL Editor de Supabase (una sola vez).
-- ============================================================

-- La RPC cargar_parte estaba reservada para n8n (que entra con service_role).
-- Para poder cargar una hoja a mano desde la app, los usuarios logueados
-- también necesitan poder llamarla. Sigue siendo security definer: valida,
-- evita duplicar bobinas y crea máquina/operario si no existen.
grant execute on function cargar_parte(jsonb) to authenticated;
