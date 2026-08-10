-- ============================================================
-- SEPARAR "ROLLERA" DE "MÁQUINA DE ORIGEN"
--
-- La hoja de control anota, en "BOBINA DE MAQUINA", la extrusora que fabricó
-- la bobina que entra como materia prima. Esa NO es la rollera que corta.
--
-- A partir de acá:
--   producciones.maquina_id     -> la ROLLERA (la máquina de la planta)
--   producciones.maquina_origen -> la extrusora que hizo la bobina (texto libre)
--
-- Así los kilos por máquina salen por rollera, y el monitoreo no se llena de
-- máquinas que en realidad son extrusoras de un proveedor.
-- Correr en el SQL Editor de Supabase (una sola vez).
-- ============================================================

alter table producciones add column if not exists maquina_origen text default '';

-- ---------- cargar_parte: ahora recibe rollera + maquina_origen ----------
create or replace function cargar_parte(datos jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_emp uuid; v_pla uuid; v_maq uuid; v_op uuid; v_prod uuid;
  v_bob uuid; v_def int; v_opb uuid;
  v_nombre_emp text; v_nombre_pla text; v_cod_rollera text; v_nombre_op text;
  v_origen_bob text;
  adv text[] := '{}';
  b jsonb;
  ins int := 0;
begin
  v_nombre_emp := coalesce(nullif(datos->>'empresa',''),'Coop El Circulo');
  insert into empresas (nombre) values (v_nombre_emp) on conflict (nombre) do nothing;
  v_emp := (select id from empresas where nombre = v_nombre_emp);

  v_nombre_pla := coalesce(nullif(datos->>'planta',''),'Rolleras');
  insert into plantas (empresa_id, nombre) values (v_emp, v_nombre_pla) on conflict (empresa_id, nombre) do nothing;
  v_pla := (select id from plantas where empresa_id = v_emp and nombre = v_nombre_pla);

  -- La rollera viene de 'rollera'. Si no vino (cargas viejas), se acepta 'maquina'
  -- para no romper nada que ya estuviera funcionando.
  v_cod_rollera := coalesce(nullif(datos->>'rollera',''), nullif(datos->>'maquina',''), 'S/D');
  insert into maquinas (planta_id, codigo) values (v_pla, v_cod_rollera) on conflict (planta_id, codigo) do nothing;
  v_maq := (select id from maquinas where planta_id = v_pla and codigo = v_cod_rollera);

  -- La extrusora que hizo la bobina: solo se guarda como dato, no crea máquinas.
  v_origen_bob := coalesce(datos->>'maquina_origen','');

  v_nombre_op := coalesce(nullif(datos->>'operario',''),'S/D');
  insert into operarios (empresa_id, nombre) values (v_emp, v_nombre_op) on conflict (empresa_id, nombre) do nothing;
  v_op := (select id from operarios where empresa_id = v_emp and nombre = v_nombre_op);

  v_prod := (select id from producciones
              where maquina_id = v_maq and fecha = (datos->>'fecha')::date and turno = datos->>'turno');

  if v_prod is not null then
    adv := adv || 'Ya existia un parte para esa rollera, fecha y turno: se agregan solo las bobinas nuevas';
  else
    insert into producciones (empresa_id, planta_id, maquina_id, operario_id, fecha, turno,
                              medida, filas, bultos, observaciones, origen, maquina_origen)
    values (v_emp, v_pla, v_maq, v_op, (datos->>'fecha')::date, datos->>'turno',
            datos->>'medida', nullif(datos->>'filas','')::int, nullif(datos->>'bultos','')::int,
            datos->>'observaciones', datos->>'origen', v_origen_bob);
    v_prod := (select id from producciones
                where maquina_id = v_maq and fecha = (datos->>'fecha')::date and turno = datos->>'turno');
  end if;

  for b in select * from jsonb_array_elements(coalesce(datos->'bobinas','[]'::jsonb)) loop
    if exists (select 1 from bobinas where produccion_id = v_prod and n_bobina = b->>'n_bobina') then
      adv := adv || ('Bobina repetida (ya estaba cargada): ' || (b->>'n_bobina'));
      continue;
    end if;

    v_opb := null;
    if coalesce(b->>'iniciales','') <> '' then
      v_opb := (select id from operarios
                 where empresa_id = v_emp
                   and (upper(coalesce(iniciales,'')) = upper(b->>'iniciales') or upper(nombre) = upper(b->>'iniciales'))
                 limit 1);
      if v_opb is null then
        insert into operarios (empresa_id, nombre, iniciales)
        values (v_emp, upper(b->>'iniciales'), upper(b->>'iniciales'))
        on conflict (empresa_id, nombre) do nothing;
        v_opb := (select id from operarios where empresa_id = v_emp and nombre = upper(b->>'iniciales'));
      end if;
    end if;

    insert into bobinas (produccion_id, n_bobina, peso, iniciales, operario_id, estado)
    values (v_prod, b->>'n_bobina', nullif(b->>'peso','')::numeric,
            nullif(upper(coalesce(b->>'iniciales','')),''), v_opb,
            nullif(upper(coalesce(b->>'estado','')),''));
    v_bob := (select id from bobinas where produccion_id = v_prod and n_bobina = b->>'n_bobina');
    ins := ins + 1;

    if coalesce(b->>'defecto','') <> '' then
      insert into defectos (nombre) values (lower(trim(b->>'defecto')))
        on conflict (nombre) do nothing;
      v_def := (select id from defectos where nombre = lower(trim(b->>'defecto')));
      insert into bobina_defectos (bobina_id, defecto_id, detalle)
      values (v_bob, v_def, b->>'defecto')
      on conflict do nothing;
    end if;
  end loop;

  if (datos ? 'scrap_empalme') or (datos ? 'scrap_rollo') then
    insert into scrap (produccion_id, empalme, rollo)
    values (v_prod, coalesce((datos->>'scrap_empalme')::numeric,0), coalesce((datos->>'scrap_rollo')::numeric,0))
    on conflict (produccion_id) do update set empalme = excluded.empalme, rollo = excluded.rollo;
  end if;

  insert into historial (empresa_id, evento, detalle)
  values (v_emp, 'carga_parte',
          jsonb_build_object('produccion_id', v_prod, 'bobinas_insertadas', ins,
                             'advertencias', to_jsonb(adv), 'origen', datos->>'origen'));

  return jsonb_build_object('ok', true, 'produccion_id', v_prod,
                            'bobinas_insertadas', ins, 'advertencias', to_jsonb(adv));
end $$;

grant execute on function cargar_parte(jsonb) to authenticated, anon;

-- ---------- Vistas: exponer la máquina de origen ----------
-- OJO: create or replace view NO permite insertar una columna en el medio ni
-- renombrar las existentes; solo agregar al final. Por eso maquina_origen va
-- última en las dos vistas, y así no hace falta borrarlas (ni sus dependientes).
create or replace view v_producciones as
select
  p.id, p.empresa_id, e.nombre as empresa, pl.nombre as planta,
  m.codigo as maquina, o.nombre as operario,
  p.fecha, p.turno, p.medida, p.filas, p.bultos, p.observaciones,
  (select count(*) from bobinas b where b.produccion_id = p.id) as bobinas,
  (select coalesce(sum(peso),0) from bobinas b where b.produccion_id = p.id) as kilos,
  (select count(*) from bobinas b where b.produccion_id = p.id and estado = 'BIEN') as bien,
  (select count(*) from bobinas b where b.produccion_id = p.id and estado = 'MAL') as mal,
  coalesce(s.empalme,0) as scrap_empalme,
  coalesce(s.rollo,0) as scrap_rollo,
  p.maquina_origen
from producciones p
join empresas e on e.id = p.empresa_id
join plantas pl on pl.id = p.planta_id
join maquinas m on m.id = p.maquina_id
left join operarios o on o.id = p.operario_id
left join scrap s on s.produccion_id = p.id;

create or replace view v_bobinas as
select
  b.id, p.empresa_id, e.nombre as empresa, pl.nombre as planta,
  m.codigo as maquina, p.fecha, p.turno, p.medida,
  op.nombre as operario_turno,
  coalesce(ob.nombre, b.iniciales) as operario_bobina,
  b.n_bobina, b.peso, b.estado,
  (select string_agg(coalesce(bd.detalle, d.nombre), ', ')
     from bobina_defectos bd left join defectos d on d.id = bd.defecto_id
    where bd.bobina_id = b.id) as defectos,
  p.id as produccion_id,
  p.maquina_origen
from bobinas b
join producciones p on p.id = b.produccion_id
join empresas e on e.id = p.empresa_id
join plantas pl on pl.id = p.planta_id
join maquinas m on m.id = p.maquina_id
left join operarios op on op.id = p.operario_id
left join operarios ob on ob.id = b.operario_id;

grant select on v_bobinas, v_producciones to anon, authenticated;
