-- ============================================================
-- ACOMODAR LOS DATOS YA CARGADOS
--
-- Solo corrige lo que es inequivoco. Lo dudoso NO se toca: se lista al final
-- para que lo mires contra la hoja de papel. Preferible dejar 6 bobinas para
-- revisar que "arreglar" 6 con un valor inventado.
--
-- Correr en el SQL Editor de Supabase. Se puede correr mas de una vez sin
-- riesgo: las condiciones dejan de cumplirse una vez aplicado.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. PESOS DIVIDIDOS POR MIL
-- La IA devolvio "47.500" como numero en vez de texto, el JSON lo leyo como
-- 47,5 y se perdieron los miles. Son 17 bobinas de 43 a 56 kg: al multiplicar
-- por mil quedan entre 43.000 y 56.000, que es el rango normal de una bobina.
-- Se toca solo lo que esta por debajo de 100 kg, que no puede ser real.
-- ─────────────────────────────────────────────────────────────
update bobinas
   set peso = peso * 1000
 where peso > 0
   and peso < 100;

-- ─────────────────────────────────────────────────────────────
-- 2. SCRAP DIVIDIDO POR MIL
-- Mismo origen. Se corrige solo en las hojas donde tambien se rompieron los
-- pesos de las bobinas, para no tocar un scrap chico que sea real.
-- ─────────────────────────────────────────────────────────────
update scrap s
   set empalme = s.empalme * 1000
 where s.empalme > 0
   and s.empalme < 100
   and exists (
     select 1 from bobinas b
      where b.produccion_id = s.produccion_id
        and b.peso between 43000 and 56000
   );

update scrap s
   set rollo = s.rollo * 1000
 where s.rollo > 0
   and s.rollo < 100
   and exists (
     select 1 from bobinas b
      where b.produccion_id = s.produccion_id
        and b.peso between 43000 and 56000
   );

-- ─────────────────────────────────────────────────────────────
-- 3. QUE QUEDO PARA REVISAR A MANO
-- Estas consultas no cambian nada, solo muestran lo que hay que mirar contra
-- el papel. Corrigilas desde la app: Reportes -> Hojas cargadas -> Corregir.
-- ─────────────────────────────────────────────────────────────

-- 3a. Bobinas con peso raro que NO se pudo determinar solo
select 'PESO DUDOSO' as caso, m.codigo as rollera, p.fecha, p.turno,
       b.n_bobina, b.peso,
       case when b.peso < 10000 then b.peso * 10 else null end as si_fuera_x10
  from bobinas b
  join producciones p on p.id = b.produccion_id
  join maquinas m on m.id = p.maquina_id
 where b.peso is not null
   and (b.peso < 10000 or b.peso > 100000)
 order by b.peso;

-- 3b. Hojas con fecha imposible (el dia y el mes suelen estar bien: casi
--     siempre lo que fallo es el anio)
select 'FECHA RARA' as caso, m.codigo as rollera, p.fecha, p.turno,
       (select count(*) from bobinas b where b.produccion_id = p.id) as bobinas,
       make_date(extract(year from current_date)::int,
                 extract(month from p.fecha)::int,
                 extract(day from p.fecha)::int) as si_fuera_este_anio
  from producciones p
  join maquinas m on m.id = p.maquina_id
 where p.fecha < current_date - interval '90 days'
    or p.fecha > current_date
 order by p.fecha;

-- 3c. Bobinas sin BIEN/MAL: no cuentan ni como buenas ni como falladas,
--     asi que falsean el porcentaje de error del reporte
select 'SIN ESTADO' as caso, m.codigo as rollera, p.fecha, p.turno, b.n_bobina, b.peso
  from bobinas b
  join producciones p on p.id = b.produccion_id
  join maquinas m on m.id = p.maquina_id
 where b.estado is null
 order by p.fecha desc;
