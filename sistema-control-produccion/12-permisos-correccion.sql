-- ============================================================
-- PERMISOS PARA CORREGIR DESDE LA APP
--
-- Cuando una politica de seguridad bloquea la fila, Supabase NO devuelve error:
-- simplemente no actualiza nada. Por eso el boton de corregir podia quedarse
-- callado sin hacer nada.
--
-- Este archivo hace tres cosas:
--   1. muestra que permisos hay hoy
--   2. los aplica (se puede repetir sin riesgo)
--   3. los muestra de nuevo para confirmar
--
-- Correr entero en el SQL Editor y mirar el ultimo resultado.
-- ============================================================

-- ── 1. ANTES ────────────────────────────────────────────────
select 'ANTES' as momento, tablename as tabla, policyname as politica, cmd as permiso
  from pg_policies
 where schemaname = 'public'
   and tablename in ('producciones','bobinas','scrap','bobina_defectos','operarios','maquinas')
 order by tablename, cmd;

-- ── 2. APLICAR ──────────────────────────────────────────────
alter table producciones     enable row level security;
alter table bobinas          enable row level security;
alter table scrap            enable row level security;
alter table bobina_defectos  enable row level security;
alter table operarios        enable row level security;

-- Encabezado de la hoja: fecha, turno, medida, bultos, observaciones
drop policy if exists "producciones_rw_auth" on producciones;
create policy "producciones_rw_auth" on producciones
  for all to authenticated using (true) with check (true);

-- Cada bobina: numero, peso, iniciales, BIEN/MAL
drop policy if exists "bobinas_rw_auth" on bobinas;
create policy "bobinas_rw_auth" on bobinas
  for all to authenticated using (true) with check (true);

-- El scrap del turno
drop policy if exists "scrap_rw_auth" on scrap;
create policy "scrap_rw_auth" on scrap
  for all to authenticated using (true) with check (true);

-- Los defectos de cada bobina
drop policy if exists "bobina_defectos_rw_auth" on bobina_defectos;
create policy "bobina_defectos_rw_auth" on bobina_defectos
  for all to authenticated using (true) with check (true);

-- Los operarios, para poder reasignar una bobina
drop policy if exists "operarios_select_auth" on operarios;
create policy "operarios_select_auth" on operarios
  for select to authenticated using (true);

-- ── 3. DESPUES ──────────────────────────────────────────────
-- Tienen que aparecer al menos: producciones ALL, bobinas ALL, scrap ALL,
-- bobina_defectos ALL, operarios SELECT, maquinas SELECT/UPDATE/INSERT/DELETE
select 'DESPUES' as momento, tablename as tabla, policyname as politica, cmd as permiso
  from pg_policies
 where schemaname = 'public'
   and tablename in ('producciones','bobinas','scrap','bobina_defectos','operarios','maquinas')
 order by tablename, cmd;
