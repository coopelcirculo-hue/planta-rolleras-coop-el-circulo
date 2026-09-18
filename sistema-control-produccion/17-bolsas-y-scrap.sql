-- ============================================================
-- 17 · MILLARES DE BOLSAS Y SCRAP IMPOSIBLE
--
-- 1. MILLARES DE BOLSAS: la medida dice todo. "45x60x20x24" = bolsa de 45x60,
--    20 bolsas por rollo y 24 rollos por bulto. Se guardan tambien las bolsas
--    (rollos x bolsas por rollo) y los reportes muestran millares de bolsas.
--
-- 2. SCRAP IMPOSIBLE: a veces la IA junta dos numeros y lee un scrap de decenas
--    de millones de kilos. Si el scrap de una hoja supera el 15% de sus kilos
--    (lo normal es 2 a 5%), se guarda un valor aproximado (lo normal de esa
--    rollera en los ultimos 2 meses) y la hoja queda marcada para corregir.
--
-- 3. Se corrige asi la hoja de Rollera 6 del 16/09 dia (Emilio Campo), que
--    tenia 57.001.500 kg de scrap de empalme y 60.506.800 kg de rollo.
--
-- Correr ENTERO en el SQL Editor de Supabase. Se puede repetir sin riesgo.
-- ============================================================


-- ── 1. Bolsas en los rollos por turno ───────────────────────────────────────
alter table rollos_turno add column if not exists bolsas_por_rollo int;
alter table rollos_turno add column if not exists bolsas bigint;

-- Las columnas nuevas van al final para no romper la vista
create or replace view v_rollos as
select r.id, r.maquina_id, m.codigo as maquina, e.nombre as empresa,
       r.fecha, r.turno, r.medida, r.bultos, r.rollos_por_bulto, r.rollos,
       r.creado_por, r.creado_en, r.bolsas_por_rollo, r.bolsas
  from rollos_turno r
  join maquinas m  on m.id = r.maquina_id
  join plantas pl  on pl.id = m.planta_id
  join empresas e  on e.id = pl.empresa_id;

grant select on v_rollos to authenticated;


-- ── 2. Guardar una hoja: con control de scrap imposible ─────────────────────
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
  v_kg numeric := 0; v_med_se numeric; v_med_sr numeric;
  v_prev jsonb; v_res jsonb;
  v_total int := 0; v_total_pesos int := 0; v_dup uuid; v_coinc int := 0; v_por_pesos boolean := false;
  v_desc_dup text; v_otras text;
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

  -- a) La MISMA carga ya se proceso (n8n reintento la misma foto)
  if v_carga is not null then
    select detalle into v_prev from historial
     where evento = 'carga_parte' and detalle->>'carga_id' = v_carga
     order by id desc limit 1;
    if v_prev is not null then return v_prev; end if;
  end if;

  -- b) ¿Se parece a una hoja ya cargada? Solo para marcarla, nunca para descartarla.
  select count(distinct norm_bobina(e->>'n_bobina')),
         count(*) filter (where (e->>'peso') ~ '^\d+(\.\d+)?$')
    into v_total, v_total_pesos
    from jsonb_array_elements(coalesce(datos->'bobinas', '[]'::jsonb)) e
   where norm_bobina(e->>'n_bobina') <> '';

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
    select to_char(p.fecha, 'DD/MM') || ' ' || p.turno || ', ' || coalesce(o.nombre, 'S/D')
           || ', ' || (select count(*) from bobinas b where b.produccion_id = p.id) || ' bobinas'
      into v_desc_dup
      from producciones p
      left join operarios o on o.id = p.operario_id
     where p.id = v_dup;
    v_resultado := 'posible_repetida';
    adv := array_append(adv, 'Se parece a la hoja ya cargada del ' || v_desc_dup || ': se guardo igual, marcada para revisar');
    v_obs := _agregar_revisar(v_obs,
      'posible hoja repetida: se parece a la hoja del ' || v_desc_dup || ' (' || v_coinc || ' bobinas iguales por '
      || case when v_por_pesos then 'peso' else 'numero y peso' end
      || '). Si es la misma foto subida dos veces, borrala. Si son hojas distintas, dejala.');
  end if;

  -- c) Otra hoja de la misma rollera, dia y turno con OTRO operario
  select string_agg(distinct coalesce(o.nombre, 'S/D'), ', ') into v_otras
    from producciones p
    left join operarios o on o.id = p.operario_id
   where p.maquina_id = v_maq and p.fecha = v_fecha and p.turno = v_turno
     and p.id is distinct from v_dup
     and upper(left(coalesce(o.nombre, ''), 4)) <> upper(left(v_nombre_op, 4));
  if v_otras is not null then
    if v_resultado = 'nueva' then v_resultado := 'nueva_mismo_turno'; end if;
    adv := array_append(adv, 'Ya hay otra hoja de esta rollera el mismo dia y turno con otro operario (' || v_otras || ')');
    v_obs := _agregar_revisar(v_obs, 'ya hay otra hoja de esta rollera el mismo dia y turno con otro operario ('
                                     || v_otras || '). Verificar fecha y turno.');
  end if;

  -- d) Scrap imposible: mas del 15% de los kilos de la hoja (lo normal es 2 a 5%).
  --    Casi siempre la IA junto dos numeros. Se pone lo normal de esta rollera en
  --    los ultimos 2 meses y se marca para corregir con el papel.
  select coalesce(sum((e->>'peso')::numeric), 0) into v_kg
    from jsonb_array_elements(coalesce(datos->'bobinas', '[]'::jsonb)) e
   where (e->>'peso') ~ '^\d+(\.\d+)?$';
  if v_kg > 0 and v_se + v_sr > v_kg * 0.15 then
    select coalesce(percentile_cont(0.5) within group (order by s.empalme), 0),
           coalesce(percentile_cont(0.5) within group (order by s.rollo), 0)
      into v_med_se, v_med_sr
      from scrap s
      join producciones p on p.id = s.produccion_id
      join lateral (select coalesce(sum(b.peso), 0) as kg from bobinas b where b.produccion_id = p.id) k on true
     where p.maquina_id = v_maq
       and p.fecha between v_fecha - 60 and v_fecha
       and k.kg > 0
       and s.empalme + s.rollo between 1 and k.kg * 0.15;
    adv := array_append(adv, 'Scrap imposible (' || v_se::bigint || ' y ' || v_sr::bigint || ' kg): se puso un valor aproximado');
    v_obs := _agregar_revisar(v_obs,
      'scrap mal leido por la IA (empalme ' || v_se::bigint || ' kg y rollo ' || v_sr::bigint
      || ' kg): se puso un valor aproximado (' || round(v_med_se) || ' y ' || round(v_med_sr)
      || ' kg, lo normal de esta rollera). Corregir con el papel.');
    v_se := round(v_med_se);
    v_sr := round(v_med_sr);
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
                              'parecida_a', v_dup,
                              'carga_id', v_carga, 'rollera', v_cod, 'origen', datos->>'origen');
  insert into historial (empresa_id, evento, detalle) values (v_emp, 'carga_parte', v_res);
  return v_res;
end $$;

grant execute on function cargar_parte(jsonb) to authenticated, anon;


-- ── 3. La hoja de esta semana con el scrap imposible ────────────────────────
-- Rollera 6 · 16/09 dia · Emilio Campo. Solo si sigue con el valor mal leido.
with arreglo as (
  update scrap
     set empalme = 3050, rollo = 11000
   where produccion_id = 'b69fb8a9-754e-443b-b127-2aa169e3a7d2'::uuid
     and empalme = 57001500
  returning produccion_id
),
nota as (
  update producciones
     set observaciones = _agregar_revisar(observaciones,
           'scrap mal leido por la IA (empalme 57.001.500 kg y rollo 60.506.800 kg): se puso un valor aproximado (3.050 y 11.000 kg, lo normal de la Rollera 6). Corregir con el papel.')
   where id in (select produccion_id from arreglo)
  returning id
)
select 'Rollera 6 16/09 dia: scrap aproximado puesto' as cambio, (select count(*) from arreglo) = 1 as ok
union all
select 'Rollera 6 16/09 dia: nota para corregir con el papel', (select count(*) from nota) = 1;
