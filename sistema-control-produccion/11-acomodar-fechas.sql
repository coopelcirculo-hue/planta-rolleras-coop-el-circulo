-- ============================================================
-- ACOMODAR LAS FECHAS MAL LEIDAS
--
-- La IA lee bien el dia y el mes; lo que confunde es el anio escrito a mano
-- ("26" leido como 20, 21 o 24). Estas 4 hojas cumplen las tres condiciones
-- para corregirlas sin riesgo:
--   · al poner 2026 la fecha cae dentro de los ultimos 90 dias
--   · no choca con ninguna otra hoja de la misma rollera, fecha y turno
--   · el dia y el mes son coherentes con el resto de la produccion
--
-- Correr en el SQL Editor. Se puede repetir sin riesgo.
-- ============================================================

update producciones p
   set fecha = make_date(2026, extract(month from p.fecha)::int, extract(day from p.fecha)::int)
  from maquinas m
 where m.id = p.maquina_id
   and extract(year from p.fecha) < 2026
   and (m.codigo, extract(month from p.fecha)::int, extract(day from p.fecha)::int, p.turno) in (
         ('6',  8, 14, 'dia'),    -- Rollera 6 · 14/08 dia   ·  6 bobinas
         ('5',  8, 18, 'noche'),  -- Rollera 5 · 18/08 noche · 17 bobinas
         ('5',  8,  4, 'noche'),  -- Rollera 5 · 04/08 noche ·  5 bobinas
         ('6',  8, 21, 'noche')   -- Rollera 6 · 21/08 noche ·  7 bobinas
       );

-- ─────────────────────────────────────────────────────────────
-- QUE QUEDO SIN TOCAR, Y POR QUE
--
-- Estas 9 hojas NO se pueden deducir: hay que mirar el papel. Son hojas reales
-- con produccion real (no son duplicados), asi que NO se borran.
--
--   El mes tambien esta mal (corregir solo el anio no alcanza):
--     · Rollera 5 · 20/01/2020 · 17 bobinas
--     · Rollera 6 · 14/10/2021 ·  7 bobinas
--     · Rollera 6 · 12/03/2026 · 10 bobinas
--     · Rollera 5 · 31/08/2026 · 16 bobinas   (fecha futura)
--     · Rollera 5 · 15/12/2026 ·  6 bobinas   (fecha futura)
--     · Rollera 5 · 16/12/2026 ·  7 bobinas   (fecha futura)
--
--   Al corregir el anio chocarian con otra hoja que ya existe, o sea que su
--   fecha real es otro dia distinto:
--     · Rollera 5 · 07/08/2020 · 12 bobinas   (bobinas 7-51, 7-32, 8-4...)
--     · Rollera 5 · 20/08/2020 · 14 bobinas   (bobinas 73, 74, 72...)
--     · Rollera 5 · 10/08/2024 · 16 bobinas   (bobinas 7-72, 7-51...)
--
-- Se corrigen desde la app: Reportes -> Hojas cargadas -> Corregir.
-- Para ubicar cada papel, buscalo por los numeros de bobina.
-- ─────────────────────────────────────────────────────────────

-- Control: que quedo fuera de rango despues de correr esto
select m.codigo as rollera, p.fecha, p.turno,
       (select count(*) from bobinas b where b.produccion_id = p.id) as bobinas
  from producciones p
  join maquinas m on m.id = p.maquina_id
 where p.fecha < current_date - interval '90 days'
    or p.fecha > current_date
 order by p.fecha;
