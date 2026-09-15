-- ============================================================
-- 15 · LIMPIEZA FINAL
--
-- 1. Reconocer una hoja repetida por los PESOS (aunque la IA lea mal los
--    numeros o la fecha). Es el mismo contenido del archivo 14.
-- 2. Borrar 3 hojas duplicadas y corregir una fecha, verificado con las fotos.
--
-- Cada borrado y cada cambio se aplica SOLO si la hoja sigue exactamente como
-- se analizo (mismas bobinas y kilos). Si alguien la toco, no pasa nada.
--
-- Correr ENTERO en el SQL Editor de Supabase. Mirar el ultimo resultado.
-- ============================================================


-- ── 1. Hojas repetidas por pesos ────────────────────────────────────────────
create or replace function cargar_parte(datos jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_emp uuid; v_pla uuid; v_maq uuid; v_op uuid; v_prod uuid;
  v_nombre_emp text; v_nombre_pla text; v_cod text; v_nombre_op text;
  v_fecha date := (datos->>'fecha')::date;
  v_turno text := datos->>'turno';
  v_carga text := nullif(datos->>'carga_id', '');
  v_obs text := coalesce(datos->>'observaciones', '');
  v_se numeric := case when (datos->>'scrap_empalme') ~ '^\d+(\.\d+)?$' then (datos->>'scrap_empalme')::numeric else 0 end;
  v_sr numeric := case when (datos->>'scrap_rollo') ~ '^\d+(\.\d+)?$' then (datos->>'scrap_rollo')::numeric else 0 end;
  v_prev jsonb; v_res jsonb;
  v_total int := 0; v_total_pesos int := 0; v_dup uuid; v_coinc int := 0; v_por_pesos boolean := false;
  v_faltan text; v_otras text;
  v_ins int; v_adv text[]; adv text[] := '{}';
  v_resultado text := 'nueva';
begin
  v_nombre_emp := coalesce(nullif(datos->>'empresa', ''), 'Coop El Circulo');
  insert into empresas (nombre) values (v_nombre_emp) on conflict (nombre) do nothing;
  v_emp := (select id from empresas where nombre = v_nombre_emp);

  v_nombre_pla := coalesce(nullif(datos->>'planta', ''), 'Rolleras');
  insert into plantas (empresa_id, nombre) values (v_emp, v_nombre_pla) on conflict (empresa_id, nombre) do nothing;
  v_pla := (select id from plantas where empresa_id = v_emp and nombre = v_nombre_pla);

  v_cod := coalesce(nullif(datos->>'rollera', ''), nullif(datos->>'maquina', ''), 'S/D');
  insert into maquinas (planta_id, codigo) values (v_pla, v_cod) on conflict (planta_id, codigo) do nothing;
  v_maq := (select id from maquinas where planta_id = v_pla and codigo = v_cod);

  v_nombre_op := coalesce(nullif(trim(datos->>'operario'), ''), 'S/D');
  v_op := _operario_id(v_emp, v_nombre_op);

  -- a) La misma carga ya se proceso (n8n reintento): se devuelve lo mismo
  if v_carga is not null then
    select detalle into v_prev from historial
     where evento = 'carga_parte' and detalle->>'carga_id' = v_carga
     order by id desc limit 1;
    if v_prev is not null then return v_prev; end if;
  end if;

  -- b) ¿La hoja ya estaba cargada?
  select count(distinct norm_bobina(e->>'n_bobina')),
         count(*) filter (where (e->>'peso') ~ '^\d+(\.\d+)?$')
    into v_total, v_total_pesos
    from jsonb_array_elements(coalesce(datos->'bobinas', '[]'::jsonb)) e
   where norm_bobina(e->>'n_bobina') <> '';

  -- b1) Por numero: 60% de las bobinas con el mismo numero y el mismo peso (±50 kg)
  if v_total >= 2 then
    select p.id, count(distinct norm_bobina(b.n_bobina))
      into v_dup, v_coinc
      from producciones p
      join bobinas b on b.produccion_id = p.id
      join jsonb_array_elements(datos->'bobinas') e
        on norm_bobina(e->>'n_bobina') = norm_bobina(b.n_bobina)
       and b.peso is not null
       and (e->>'peso') ~ '^\d+(\.\d+)?$'
       and abs(b.peso - (e->>'peso')::numeric) <= 50
     where p.maquina_id = v_maq
       and (p.fecha between v_fecha - 4 and v_fecha + 4 or p.creado_en > now() - interval '4 days')
     group by p.id
     order by 2 desc
     limit 1;
    if v_dup is not null and v_coinc < greatest(2, ceil(v_total * 0.6)) then
      v_dup := null;
    end if;
  end if;

  -- b2) Por pesos, aunque los numeros o la fecha se hayan leido mal: el 80% de
  --     los pesos exactos (minimo 3) y una cantidad de bobinas parecida
  if v_dup is null and v_total_pesos >= 3 then
    select x.id, x.coinc into v_dup, v_coinc
      from (
        select p.id,
               (select coalesce(sum(least(bp.n, ip.n)), 0)
                  from (select peso, count(*) as n from bobinas
                         where produccion_id = p.id and peso is not null group by peso) bp
                  join (select (e->>'peso')::numeric as peso, count(*) as n
                          from jsonb_array_elements(datos->'bobinas') e
                         where (e->>'peso') ~ '^\d+(\.\d+)?$' group by 1) ip
                    on ip.peso = bp.peso) as coinc,
               (select count(*) from bobinas where produccion_id = p.id) as nb
          from producciones p
         where p.maquina_id = v_maq
           and (p.creado_en > now() - interval '45 days' or p.fecha between v_fecha - 45 and v_fecha + 45)
      ) x
     where x.coinc >= greatest(3, ceil(v_total_pesos * 0.8))
       and abs(x.nb - v_total_pesos) <= 2
     order by x.coinc desc
     limit 1;
    v_por_pesos := v_dup is not null;
  end if;

  if v_dup is not null then
    -- Si se reconocio por numero, se avisa de las bobinas de la foto que no estan.
    -- Si fue por pesos, los numeros estan mal leidos: no se marca nada.
    if not v_por_pesos then
      select string_agg(e->>'n_bobina', ', ') into v_faltan
        from jsonb_array_elements(datos->'bobinas') e
       where norm_bobina(e->>'n_bobina') <> ''
         and not exists (select 1 from bobinas b
                          where b.produccion_id = v_dup
                            and norm_bobina(b.n_bobina) = norm_bobina(e->>'n_bobina'));
      if v_faltan is not null then
        adv := array_append(adv, 'Esta foto trae bobinas que no estan en la hoja ya cargada: ' || v_faltan);
        update producciones
           set observaciones = _agregar_revisar(observaciones,
                 'al volver a subir la hoja aparecieron bobinas que no estan cargadas (' || v_faltan || ')')
         where id = v_dup
           and coalesce(observaciones, '') not like '%(' || v_faltan || ')%';
      end if;
    end if;
    if v_se + v_sr > 0 then
      insert into scrap (produccion_id, empalme, rollo) values (v_dup, v_se, v_sr)
      on conflict (produccion_id) do update
        set empalme = excluded.empalme, rollo = excluded.rollo
      where scrap.empalme + scrap.rollo = 0;
    end if;
    v_res := jsonb_build_object('ok', true, 'resultado', 'ya_cargada', 'produccion_id', v_dup,
                                'bobinas_insertadas', 0, 'advertencias', to_jsonb(adv),
                                'reconocida_por', case when v_por_pesos then 'pesos' else 'numeros' end,
                                'carga_id', v_carga, 'rollera', v_cod, 'origen', datos->>'origen');
    insert into historial (empresa_id, evento, detalle) values (v_emp, 'carga_parte', v_res);
    return v_res;
  end if;

  -- c) Otra hoja de la misma rollera, dia y turno con OTRO operario
  select string_agg(distinct coalesce(o.nombre, 'S/D'), ', ') into v_otras
    from producciones p
    left join operarios o on o.id = p.operario_id
   where p.maquina_id = v_maq and p.fecha = v_fecha and p.turno = v_turno
     and upper(left(coalesce(o.nombre, ''), 4)) <> upper(left(v_nombre_op, 4));
  if v_otras is not null then
    v_resultado := 'nueva_mismo_turno';
    adv := array_append(adv, 'Ya hay otra hoja de esta rollera el mismo dia y turno con otro operario (' || v_otras || ')');
    v_obs := _agregar_revisar(v_obs, 'ya hay otra hoja de esta rollera el mismo dia y turno con otro operario ('
                                     || v_otras || '). Verificar fecha y turno.');
  end if;

  insert into producciones (empresa_id, planta_id, maquina_id, operario_id, fecha, turno,
                            medida, filas, bultos, observaciones, origen, maquina_origen, carga_id)
  values (v_emp, v_pla, v_maq, v_op, v_fecha, v_turno,
          datos->>'medida',
          case when (datos->>'filas') ~ '^\d{1,6}$' then (datos->>'filas')::int else null end,
          case when (datos->>'bultos') ~ '^\d{1,6}$' then (datos->>'bultos')::int else null end,
          v_obs, datos->>'origen', coalesce(datos->>'maquina_origen', ''), v_carga)
  returning id into v_prod;

  select * into v_ins, v_adv from _insertar_bobinas(v_prod, v_emp, datos->'bobinas');
  adv := adv || v_adv;

  if (datos ? 'scrap_empalme') or (datos ? 'scrap_rollo') then
    insert into scrap (produccion_id, empalme, rollo) values (v_prod, v_se, v_sr)
    on conflict (produccion_id) do update set empalme = excluded.empalme, rollo = excluded.rollo;
  end if;

  v_res := jsonb_build_object('ok', true, 'resultado', v_resultado, 'produccion_id', v_prod,
                              'bobinas_insertadas', v_ins, 'advertencias', to_jsonb(adv),
                              'carga_id', v_carga, 'rollera', v_cod, 'origen', datos->>'origen');
  insert into historial (empresa_id, evento, detalle) values (v_emp, 'carga_parte', v_res);
  return v_res;
end $$;

grant execute on function cargar_parte(jsonb) to authenticated, anon;


-- ── 2. Duplicadas y fecha, verificado con las fotos ─────────────────────────
with
-- Rollera 5 · 04/09 noche · Diego Ortega: la misma hoja entro 2 veces mas al
-- reenviar fotos que habian fallado (la IA leyo mal los numeros y, en una, la
-- fecha). Se deja la que se verifico con la foto (489066c8).
borrar_diego_1 as (
  delete from producciones p
   where p.id = '11b038c8-d090-44ff-a438-eaa48c10a30d'::uuid
     and (select count(*) from bobinas b where b.produccion_id = p.id) = 9
     and (select coalesce(sum(peso), 0) from bobinas b where b.produccion_id = p.id) = 426550
  returning p.id
),
borrar_diego_2 as (
  delete from producciones p
   where p.id = '48cffcd4-eb5e-43c8-9537-bd0fc06162fd'::uuid
     and (select count(*) from bobinas b where b.produccion_id = p.id) = 9
     and (select coalesce(sum(peso), 0) from bobinas b where b.produccion_id = p.id) = 426550
  returning p.id
),
-- Rollera 5 · "07/08/2020 noche": es la hoja del 07/08/2026 (10 de 11 pesos
-- exactos iguales). El anio esta mal leido. Se deja la de 2026.
borrar_2020 as (
  delete from producciones p
   where p.id = 'f3a7d155-be7b-4cb6-b9c5-9a25885c4b97'::uuid
     and (select count(*) from bobinas b where b.produccion_id = p.id) = 12
     and (select coalesce(sum(peso), 0) from bobinas b where b.produccion_id = p.id) = 534100
  returning p.id
),
nota_0708 as (
  update producciones
     set observaciones = _agregar_revisar(observaciones,
           'habia otra copia de esta hoja cargada como 07/08/2020 turno noche, que se borro. Esa copia tenia la bobina 7-51 dos veces (43.400 y 44.200 kg) donde aca figura la 51 con 44.000 kg. Verificar con el papel el turno y esa bobina.')
   where id = '00ed5f92-a7a4-48b0-b0b0-f52ae7809278'::uuid
     and exists (select 1 from borrar_2020)
     and coalesce(observaciones, '') not like '%07/08/2020%'
  returning id
),
-- Rollera 6 · Emilio Campo · 12 bobinas: la foto dice "2/9/26" (la IA tomo las
-- barras como un 1 y leyo "21"). No habia hoja de R6 del 02/09 dia.
fecha_emilio as (
  update producciones p
     set fecha = '2026-09-02',
         observaciones = _agregar_revisar(p.observaciones,
           'fecha corregida con la foto: dice 2/9/26 (la IA habia leido 21/08).')
   where p.id = '58047836-770a-4769-a45e-86f6844d91a8'::uuid
     and p.fecha = '2026-08-21'
     and (select count(*) from bobinas b where b.produccion_id = p.id) = 12
     and (select coalesce(sum(peso), 0) from bobinas b where b.produccion_id = p.id) = 619650
  returning p.id
),
-- La hoja de Diego ya verificada: el reenvio le agrego una nota por la "7-25",
-- que es la 2-25 mal leida. Se quita.
nota_diego as (
  update producciones
     set observaciones = replace(observaciones,
           ' | al volver a subir la hoja aparecieron bobinas que no estan cargadas (7-25)', '')
   where id = '489066c8-e5fd-4699-9913-a1383e6b8391'::uuid
     and observaciones like '%(7-25)%'
  returning id
)
select 'R5 04/09 noche Diego: copia duplicada 1 borrada' as cambio, (select count(*) from borrar_diego_1) = 1 as ok
union all select 'R5 04/09 noche Diego: copia duplicada 2 (cargada como 14/09) borrada', (select count(*) from borrar_diego_2) = 1
union all select 'R5 07/08/2020 noche: copia con el anio mal leido borrada', (select count(*) from borrar_2020) = 1
union all select 'R5 07/08/2026 dia: nota sobre la copia borrada', (select count(*) from nota_0708) = 1
union all select 'R6 Emilio 12 bobinas: fecha pasada al 02/09 dia', (select count(*) from fecha_emilio) = 1
union all select 'R5 04/09 noche Diego: nota de 7-25 quitada', (select count(*) from nota_diego) = 1;
