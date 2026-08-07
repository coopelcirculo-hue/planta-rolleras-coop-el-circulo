-- ============================================================
-- BLOQUE 3 de 3: SEGURIDAD Y DATOS INICIALES
-- Ejecutar despues de que el Bloque 2 haya corrido sin errores
-- ============================================================

-- Las tablas quedan cerradas para el anon key; el dashboard lee solo las
-- vistas. n8n usa la service_role key (pasa por encima de RLS).

alter table empresas enable row level security;
alter table plantas enable row level security;
alter table maquinas enable row level security;
alter table operarios enable row level security;
alter table defectos enable row level security;
alter table producciones enable row level security;
alter table bobinas enable row level security;
alter table bobina_defectos enable row level security;
alter table scrap enable row level security;
alter table historial enable row level security;

grant select on v_bobinas, v_producciones, v_produccion_diaria, v_produccion_semanal,
                v_produccion_mensual, v_por_maquina, v_por_operario, v_por_turno,
                v_defectos, v_scrap
to anon, authenticated;

revoke execute on function cargar_parte(jsonb) from anon, authenticated;
revoke execute on function consulta_lectura(text) from anon, authenticated;

-- ---------- DATOS INICIALES ----------
insert into empresas (nombre) values ('Dottiplast') on conflict do nothing;
insert into defectos (nombre) values ('arrugas'), ('fuelle'), ('grueso'), ('corrido') on conflict do nothing;

select 'BLOQUE 3 OK: seguridad y datos iniciales aplicados' as resultado;
