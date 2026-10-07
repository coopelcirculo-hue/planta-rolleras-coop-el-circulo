-- ============================================================
-- 24 · CÓMO TERMINA EL PALET DE CADA PRODUCTO
--
-- Cuando un cliente pide una medida nueva, además de la bolsa hay que saber
-- cómo se entrega: cuántos paquetes por cama, cuántas camas, qué etiqueta
-- lleva y cómo se arma. Hoy eso está en la cabeza de cada uno y cambia según
-- quién lo arma; acá queda escrito al lado del producto.
--
-- Correr ENTERO en el SQL Editor de Supabase. Se puede repetir sin riesgo.
-- ============================================================

alter table productos add column if not exists paquetes_por_cama int;
alter table productos add column if not exists camas_por_palet int;
alter table productos add column if not exists paquetes_por_palet int;
alter table productos add column if not exists etiqueta text default '';
alter table productos add column if not exists armado text default '';

-- Si alguien carga las camas y los paquetes por cama y no el total, se calcula.
update productos
   set paquetes_por_palet = paquetes_por_cama * camas_por_palet
 where paquetes_por_palet is null
   and paquetes_por_cama is not null
   and camas_por_palet is not null;

-- Control: tienen que aparecer las columnas nuevas.
select column_name, data_type
  from information_schema.columns
 where table_name = 'productos'
   and column_name in ('paquetes_por_cama','camas_por_palet','paquetes_por_palet','etiqueta','armado')
 order by column_name;
