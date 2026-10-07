-- ============================================================
-- 22 · COLOR DEL PRODUCTO
--
-- La bolsa puede ser NEGRA o de color, y si es de color hay que saber cuál:
-- la misma medida del mismo cliente en negro y en rojo son dos productos
-- distintos (distinto material, distinto precio, y no se mezclan).
--
-- Correr ENTERO en el SQL Editor de Supabase. Se puede repetir sin riesgo.
-- ============================================================

alter table productos add column if not exists color text default '';

-- Antes un cliente no podía tener dos veces la misma medida; ahora sí, si son
-- de colores distintos.
drop index if exists productos_cliente_medida_idx;
create unique index if not exists productos_cliente_medida_color_idx
  on productos (empresa, cliente, medida, coalesce(color, ''));

-- Control: tiene que listar la columna color.
select column_name, data_type
  from information_schema.columns
 where table_name = 'productos'
 order by ordinal_position;
