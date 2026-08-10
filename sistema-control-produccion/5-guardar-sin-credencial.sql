-- ============================================================
-- Permitir que n8n guarde las hojas usando la clave pública (anon),
-- para no tener que configurar la service_role como credencial.
-- Correr en el SQL Editor de Supabase (una sola vez).
-- ============================================================

-- cargar_parte es security definer: valida, evita bobinas duplicadas y crea
-- máquina/operario si no existen. Devuelve solo un resumen, no lee datos.
grant execute on function cargar_parte(jsonb) to anon;

-- OJO, a tener en cuenta:
-- La clave anon está a la vista en el código de la app, así que a partir de acá
-- cualquiera que la encuentre podría insertar partes de producción falsos.
-- No puede leer nada que no fuera ya público, ni borrar ni modificar lo cargado.
-- Si algún día molesta, se revierte con:
--     revoke execute on function cargar_parte(jsonb) from anon;
-- y se vuelve a usar la credencial service_role en n8n.

-- consulta_lectura NO se abre: permite hacer SELECT libres sobre toda la base.
-- El agente de consultas por texto sigue necesitando la credencial service_role.
