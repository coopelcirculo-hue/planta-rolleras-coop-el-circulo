-- ============================================================
-- PERMITIR CORREGIR HOJAS Y BOBINAS DESDE LA APP
--
-- Hasta ahora la app solo podía leer las vistas y cargar por RPC. Cuando la IA
-- lee mal una fecha o un peso, había que entrar al SQL Editor. Con esto se
-- corrige desde el dashboard.
-- Correr en el SQL Editor de Supabase (una sola vez).
-- ============================================================

-- Leer y corregir el encabezado de la hoja (fecha, turno, medida, bultos...)
drop policy if exists "producciones_rw_auth" on producciones;
create policy "producciones_rw_auth" on producciones
  for all to authenticated using (true) with check (true);

-- Leer y corregir cada bobina (número, peso, iniciales, BIEN/MAL)
drop policy if exists "bobinas_rw_auth" on bobinas;
create policy "bobinas_rw_auth" on bobinas
  for all to authenticated using (true) with check (true);

-- El scrap del turno
drop policy if exists "scrap_rw_auth" on scrap;
create policy "scrap_rw_auth" on scrap
  for all to authenticated using (true) with check (true);

-- Los defectos asociados a una bobina (para poder quitarlos si se leyeron mal)
drop policy if exists "bobina_defectos_rw_auth" on bobina_defectos;
create policy "bobina_defectos_rw_auth" on bobina_defectos
  for all to authenticated using (true) with check (true);

-- Los operarios, para poder corregir a quién se le asignó una bobina
drop policy if exists "operarios_select_auth" on operarios;
create policy "operarios_select_auth" on operarios
  for select to authenticated using (true);

-- Nota: esto habilita a cualquier usuario logueado de la app a editar y borrar
-- producción. Como el acceso es con usuario y contraseña y la tablet queda en la
-- planta, es el nivel de control que corresponde. Si algún día hace falta que
-- solo algunos puedan corregir, se agrega un campo de rol en la tabla usuarios.
