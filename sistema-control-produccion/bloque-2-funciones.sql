-- ============================================================
-- BLOQUE 2 de 3: FUNCIONES (RPC)
-- Ejecutar despues de que el Bloque 1 haya corrido sin errores
-- ============================================================

-- ---------- RPC: carga transaccional de un parte ----------
-- n8n llama esta funcion con el JSON validado. Resuelve/crea empresa,
-- planta, maquina y operarios; inserta produccion, bobinas (sin duplicar),
-- defectos y scrap; registra historial. Devuelve advertencias.

create or replace function cargar_parte(datos jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_emp uuid; v_pla uuid; v_maq uuid; v_op uuid; v_prod uuid;
  v_bob uuid; v_def int; v_opb uuid;
  v_nombre_emp text; v_nombre_pla text; v_cod_maq text; v_nombre_op text;
  adv text[] := '{}';
  b jsonb;
  ins int := 0;
begin
  v_nombre_emp := coalesce(nullif(datos->>'empresa',''),'Dottiplast');
  insert into empresas (nombre) values (v_nombre_emp) on conflict (nombre) do nothing;
  v_emp := (select id from empresas where nombre = v_nombre_emp);

  v_nombre_pla := coalesce(nullif(datos->>'planta',''),'Planta principal');
  insert into plantas (empresa_id, nombre) values (v_emp, v_nombre_pla) on conflict (empresa_id, nombre) do nothing;
  v_pla := (select id from plantas where empresa_id = v_emp and nombre = v_nombre_pla);

  v_cod_maq := coalesce(nullif(datos->>'maquina',''),'S/D');
  insert into maquinas (planta_id, codigo) values (v_pla, v_cod_maq) on conflict (planta_id, codigo) do nothing;
  v_maq := (select id from maquinas where planta_id = v_pla and codigo = v_cod_maq);

  v_nombre_op := coalesce(nullif(datos->>'operario',''),'S/D');
  insert into operarios (empresa_id, nombre) values (v_emp, v_nombre_op) on conflict (empresa_id, nombre) do nothing;
  v_op := (select id from operarios where empresa_id = v_emp and nombre = v_nombre_op);

  v_prod := (select id from producciones
              where maquina_id = v_maq and fecha = (datos->>'fecha')::date and turno = datos->>'turno');

  if v_prod is not null then
    adv := adv || 'Ya existia un parte para esa maquina, fecha y turno: se agregan solo las bobinas nuevas';
  else
    insert into producciones (empresa_id, planta_id, maquina_id, operario_id, fecha, turno,
                              medida, filas, bultos, observaciones, origen)
    values (v_emp, v_pla, v_maq, v_op, (datos->>'fecha')::date, datos->>'turno',
            datos->>'medida', nullif(datos->>'filas','')::int, nullif(datos->>'bultos','')::int,
            datos->>'observaciones', datos->>'origen');
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

-- ---------- RPC: consultas de solo lectura para el agente IA ----------

create or replace function consulta_lectura(sql text)
returns jsonb
language plpgsql
security definer
as $$
declare
  resultado jsonb;
  limpio text;
begin
  limpio := regexp_replace(trim(sql), ';\s*$', '');
  if limpio !~* '^\s*select' then
    raise exception 'Solo se permiten consultas SELECT';
  end if;
  if position(';' in limpio) > 0 then
    raise exception 'No se permiten multiples sentencias';
  end if;
  if limpio ~* '\m(insert|update|delete|drop|alter|create|grant|revoke|truncate|copy)\M' then
    raise exception 'Solo se permiten consultas de lectura';
  end if;
  execute 'set local statement_timeout = ''5s''';
  execute format('select coalesce(jsonb_agg(t), ''[]''::jsonb) from (%s) t', limpio)
    into resultado;
  return resultado;
end $$;

select 'BLOQUE 2 OK: funciones creadas' as resultado;
