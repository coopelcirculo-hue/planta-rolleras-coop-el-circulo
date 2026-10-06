-- ============================================================
-- 20 · LOS PESOS PASAN A KILOS DE VERDAD
--
-- En la hoja el peso se escribe "45.650" = 45 kilos con 650 gramos. La lectura
-- borraba la coma y guardaba 45650, mil veces mas. Por eso la app mostraba
-- "9.379.319 kg" en una semana cuando en realidad eran 9.379 kg.
--
-- Esto convierte lo ya cargado: bobinas y scrap quedan en kilos.
-- Los porcentajes (scrap %, error %) no cambian: ya estaban bien.
--
-- Se puede correr varias veces sin riesgo: solo toca lo que todavia esta en
-- gramos (bobinas de mas de 500 "kg", y scrap mas grande que toda la hoja).
-- Correr DESPUES de que n8n quedo arreglado (ya esta hecho).
-- ============================================================

begin;

-- ── 1. Bobinas: 45650 -> 45,650 kg ──────────────────────────────────────────
-- Una bobina real pesa entre 15 y 90 kg, asi que cualquier valor arriba de 500
-- esta en gramos. Las que quedan raras igual siguen marcadas para revisar.
update bobinas
   set peso = round(peso / 1000.0, 3)
 where peso is not null
   and peso > 500;

-- ── 2. Scrap: se compara contra lo que produjo la hoja ──────────────────────
-- Ya convertidas las bobinas, una hoja pesa unos cientos de kilos. Si el scrap
-- es mas grande que TODO lo que produjo esa hoja, es que esta en gramos.
update scrap s
   set empalme = round(s.empalme / 1000.0, 3),
       rollo   = round(s.rollo   / 1000.0, 3)
  from (
    select b.produccion_id, sum(coalesce(b.peso, 0)) as kilos
      from bobinas b
     group by b.produccion_id
  ) h
 where h.produccion_id = s.produccion_id
   and h.kilos > 0
   and (s.empalme + s.rollo) > h.kilos;

commit;

-- ── Control: asi tiene que quedar ──────────────────────────────────────────
-- Una bobina entre 15 y 90 kg, una hoja entre 150 y 900 kg, scrap de 2 a 5%.
select 'bobinas' as que,
       round(min(peso), 2) as minimo,
       round(avg(peso), 2) as promedio,
       round(max(peso), 2) as maximo,
       count(*) as cantidad
  from bobinas where peso is not null
union all
select 'kilos por hoja',
       round(min(kilos), 2), round(avg(kilos), 2), round(max(kilos), 2), count(*)
  from (select produccion_id, sum(peso) as kilos from bobinas where peso is not null group by produccion_id) x
union all
select 'scrap por hoja',
       round(min(empalme + rollo), 2), round(avg(empalme + rollo), 2),
       round(max(empalme + rollo), 2), count(*)
  from scrap;
