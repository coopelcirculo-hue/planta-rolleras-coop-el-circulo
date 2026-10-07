-- ============================================================
-- 25 · FOTO DEL PRODUCTO
--
-- Una foto de la bolsa terminada al lado de cada medida: así el que arma o el
-- que controla ve de qué están hablando, sin interpretar.
--
-- Las fotos se guardan en el Storage de Supabase (bucket "productos") y en la
-- tabla queda solo el link. Se achican en la app antes de subirlas.
--
-- Correr ENTERO en el SQL Editor de Supabase. Se puede repetir sin riesgo.
-- ============================================================

-- El link de la foto, al lado del producto
alter table productos add column if not exists foto text default '';

-- Lugar donde se guardan las fotos
insert into storage.buckets (id, name, public)
values ('productos', 'productos', true)
on conflict (id) do update set public = true;

-- Ver la foto puede cualquiera que tenga el link (es una foto de producto, y
-- así se ve también en la ficha impresa); subir, cambiar o borrar, solo los
-- usuarios de la app.
drop policy if exists "fotos_producto_leer" on storage.objects;
create policy "fotos_producto_leer" on storage.objects
  for select using (bucket_id = 'productos');

drop policy if exists "fotos_producto_subir" on storage.objects;
create policy "fotos_producto_subir" on storage.objects
  for insert to authenticated with check (bucket_id = 'productos');

drop policy if exists "fotos_producto_cambiar" on storage.objects;
create policy "fotos_producto_cambiar" on storage.objects
  for update to authenticated using (bucket_id = 'productos');

drop policy if exists "fotos_producto_borrar" on storage.objects;
create policy "fotos_producto_borrar" on storage.objects
  for delete to authenticated using (bucket_id = 'productos');

-- Control: tiene que decir "listo" y mostrar el bucket productos como público.
select 'listo' as estado, id, public from storage.buckets where id = 'productos';
