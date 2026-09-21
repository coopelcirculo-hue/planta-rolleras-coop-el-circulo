-- ============================================================
-- 18 · CORRECCIONES VERIFICADAS CON LAS FOTOS DE LAS HOJAS
--
-- Cada cambio se comprobo mirando la foto original guardada en n8n.
-- Cada uno se aplica SOLO si la hoja sigue exactamente como se reviso
-- (mismas observaciones o mismo scrap). Si alguien la toco, se saltea.
--
-- Correr ENTERO en el SQL Editor de Supabase. Mirar el ultimo resultado:
-- cada fila tiene que decir true.
-- ============================================================

with
-- ── Rollera 6 · 16/09 dia · Emilio Campo ────────────────────────────────────
-- El scrap estaba escrito como suma: empalme 5.700 + 1.500 y rollo 6.050 + 6.800.
-- La IA pego los numeros (57001500 y 60506800).
scrap_emilio as (
  update scrap set empalme = 7200, rollo = 12850
   where produccion_id = 'b69fb8a9-754e-443b-b127-2aa169e3a7d2'::uuid
     and empalme = 3050 and rollo = 11000
  returning produccion_id
),
obs_emilio as (
  update producciones
     set observaciones = 'TURNO TRABAJADO CON NORMALIDAD. UNAR VEZ FINALIZADO EL PALET HACER OTRO IGUAL | Nota: scrap corregido con la foto (empalme 5.700 + 1.500, rollo 6.050 + 6.800).'
   where id in (select produccion_id from scrap_emilio)
  returning id
),

-- ── Rollera 6 · 15/09 · Tobias ──────────────────────────────────────────────
-- En la hoja no esta marcado ni Dia ni Noche (la IA puso dia por defecto).
-- La de dia de esa fecha es de Emilio Campo y no habia ninguna de noche.
tobias_15 as (
  update producciones
     set turno = 'noche',
         observaciones = 'Turno TRABAJADO con normalidad, MUY mal las bobinas 43/14. | Nota: en la hoja no esta marcado el turno; se paso a noche porque la hoja de dia de esa fecha es de Emilio Campo.'
   where id = 'cd1e6f19-1700-4ac8-96eb-d219d4e2c49a'::uuid
     and turno = 'dia'
     and observaciones = 'Turno TRABAJADO con normalidad, MUY mal las bobinas 43/14. | ⚠ REVISAR: ya hay otra hoja de esta rollera el mismo dia y turno con otro operario (Emilio campo). Verificar fecha y turno.'
  returning id
),

-- ── Diego Ortega · 17/09 noche ──────────────────────────────────────────────
-- Se subio como Rollera 6, pero la hoja dice "Rollera 5". La 2-24 esta Mal
-- (el operario marco Mal, fuelle y corrida en el renglon de abajo).
diego_17 as (
  update producciones p
     set maquina_id = (select m.id from maquinas m where m.planta_id = p.planta_id and m.codigo = '5'),
         observaciones = 'Nota: se habia subido como Rollera 6; la hoja dice Rollera 5.'
   where p.id = 'a6d97d6f-d65f-43de-ab76-6dd2092318fb'::uuid
     and coalesce(p.observaciones, '') = ''
     and exists (select 1 from maquinas m where m.planta_id = p.planta_id and m.codigo = '5')
  returning p.id
),
diego_17_bobina as (
  update bobinas set estado = 'MAL'
   where produccion_id = 'a6d97d6f-d65f-43de-ab76-6dd2092318fb'::uuid
     and n_bobina = '224' and estado is null
  returning id
),

-- ── Rollera 5 · 18/09 dia · NAZARENO: la 2-25 esta Mal ──────────────────────
nazareno_18 as (
  update bobinas set estado = 'MAL'
   where produccion_id = 'b20ecfaf-a5fe-4d9b-ac6f-3bcc02f594cb'::uuid
     and n_bobina = '225' and estado is null
  returning id
),
nazareno_18_obs as (
  update producciones set observaciones = 'BUEN FUNCIONAMIENTO. MAL ESTADO DE BOBINAS'
   where id = 'b20ecfaf-a5fe-4d9b-ac6f-3bcc02f594cb'::uuid
     and observaciones = 'BUEN FUNCIONAMIENTO. MAL ESTADO DE BOBINAS | ⚠ REVISAR: Bobina 225: estado BIEN/MAL sin marcar o ilegible'
  returning id
),

-- ── Rollera 6 · 14/09 noche · Tobias: la 1-8 esta Mal (ya tenia estado) ─────
tobias_14_obs as (
  update producciones set observaciones = 'TURNO TRABAJADO CON NORMALIDAD, PESIMO ESTADO DE LAS bobinas!'
   where id = '5ec952f6-5e57-4e1f-ab2d-bb92df616850'::uuid
     and observaciones = 'TURNO TRABAJADO CON NORMALIDAD, PESIMO ESTADO DE LAS bobinas! | ⚠ REVISAR: Bobina 18: estado BIEN/MAL sin marcar o ilegible'
  returning id
),

-- ── Rollera 6 · Tobias · 6 bobinas ──────────────────────────────────────────
-- La foto dice 17/09 noche; alguien la paso a mano al 18/09 y se respeta.
-- Se quita el aviso de "otra hoja del mismo turno" (la de Diego era de la R5).
tobias_18_obs as (
  update producciones set observaciones = 'TURNO TRABAJADO CON NORMALIDAD. | Nota: la foto dice 17/09 noche; la fecha se cambio a mano al 18/09.'
   where id = '0b94ca8b-d0c2-453a-afdb-7b9c98ae0d49'::uuid
     and observaciones = 'TURNO TRABAJADO CON NORMALIDAD. | ⚠ REVISAR: ya hay otra hoja de esta rollera el mismo dia y turno con otro operario (Diego Ortega). Verificar fecha y turno.'
  returning id
),

-- ── Rollera 5 · 07/09: Diego es del turno DIA, NAZARENO de noche ────────────
diego_07 as (
  update producciones set turno = 'dia', observaciones = 'Nota: verificada con la foto: turno dia.'
   where id = 'b3e01222-3061-41e1-8306-8384943af1ef'::uuid
     and turno = 'noche'
     and observaciones = '⚠ REVISAR: estaba mezclada con la hoja de NAZARENO del mismo dia y turno. Una de las dos tiene la fecha o el turno mal: verificar con el papel.'
  returning id
),
nazareno_07 as (
  update producciones set observaciones = 'Nota: verificada con la foto: turno noche.'
   where id = 'f7a17a54-260d-46c8-abb4-27b911cb2ce8'::uuid
     and observaciones = '⚠ REVISAR: estaba mezclada con la hoja de Diego Ortega del mismo dia y turno. Una de las dos tiene la fecha o el turno mal: verificar con el papel.'
  returning id
),

-- ── Rollera 5 · 09/09: Juan Dotti es del turno DIA, NAZARENO de noche ───────
juan_09 as (
  update producciones set turno = 'dia', observaciones = 'inconvenientes con las etiquetas, temp. Bobinas. quedo funcionando correctamente. | Nota: verificada con la foto: turno dia.'
   where id = '066699ca-49c8-4695-a1d9-c8fa45845551'::uuid
     and turno = 'noche'
     and observaciones = 'inconvenientes con las etiquetas, temp. Bobinas. quedo funcionando correctamente. | ⚠ REVISAR: estaba mezclada con la hoja de NAZARENO del mismo dia y turno. Una de las dos tiene la fecha o el turno mal: verificar con el papel.'
  returning id
),
nazareno_09 as (
  update producciones set observaciones = 'PERFECTO FUNCIONAMIENTO DE LA MAQUINA. | Nota: verificada con la foto: turno noche.'
   where id = '4c138787-20aa-4e48-9c95-92f0c9047772'::uuid
     and observaciones = 'PERFECTO FUNCIONAMIENTO DE LA MAQUINA. | ⚠ REVISAR: Bobina 744: estado BIEN/MAL sin marcar o ilegible | estaba mezclada con la hoja de Juan Dotti del mismo dia y turno. Una de las dos tiene la fecha o el turno mal: verificar con el papel.'
  returning id
),
nazareno_09_bobina as (
  update bobinas set estado = 'MAL'
   where produccion_id = '4c138787-20aa-4e48-9c95-92f0c9047772'::uuid
     and n_bobina = '744' and estado is null
  returning id
),

-- ── Notas de correcciones que ya estan hechas: dejan de estar "para revisar" ─
notas_resueltas as (
  update producciones p
     set observaciones = n.nueva
    from (values
      ('24b7a197-f3de-40cf-8949-b0b9490cf4b2'::uuid,
       'LADO A REGULADO FALTA CONTROLAR TEMPERATURA. LADO B FALTA REGULAR. | ⚠ REVISAR: se quitaron 15 bobinas de Juan Dotti que estaban sumadas a esta hoja: son las mismas de su hoja del 02/09 noche, que ya esta cargada aparte.',
       'LADO A REGULADO FALTA CONTROLAR TEMPERATURA. LADO B FALTA REGULAR. | Nota: se quitaron 15 bobinas de Juan Dotti que estaban repetidas (su hoja del 02/09 noche ya esta cargada aparte).'),
      ('58047836-770a-4769-a45e-86f6844d91a8'::uuid,
       'TURNO TRABAJADO CON NORMALIDAD -- TERMINAR PALET Y HACER OTRO IGUAL | ⚠ REVISAR: fecha corregida con la foto: dice 2/9/26 (la IA habia leido 21/08).',
       'TURNO TRABAJADO CON NORMALIDAD -- TERMINAR PALET Y HACER OTRO IGUAL | Nota: fecha corregida con la foto (dice 2/9/26).'),
      ('489066c8-e5fd-4699-9913-a1383e6b8391'::uuid,
       '80x110x10*50 Verde Granel: 59 Bultos, 80+110+10*50 Leito (63) Bultos 1.024 | ⚠ REVISAR: verificada con la foto: 04/09 noche es correcta. | se borraron 16 bobinas duplicadas: la misma hoja se subio otra vez y la IA leyo mal algunos numeros (525 por 725, 14 por 74, 110 por 710) con los mismos pesos.',
       '80x110x10*50 Verde Granel: 59 Bultos, 80+110+10*50 Leito (63) Bultos 1.024 | Nota: verificada con la foto.'),
      ('9a5b6a3e-f1fe-45dd-9b99-da2c85b8b2b7'::uuid,
       'Turno TRABAJADO CON NORMALIDAD. | ⚠ REVISAR: se separo la hoja de Emilio Campo que estaba sumada a esta: segun su foto es del turno noche.',
       'Turno TRABAJADO CON NORMALIDAD.'),
      ('b983ed6d-3fd3-413c-bcd6-1e4c7baa520b'::uuid,
       'TURNO TRABAJO CON NORMALIDAD... TERMINAR PALET Y CAMBIAR A 50X70X20X21 (MR. TRAPO) | ⚠ REVISAR: verificada con la foto: es del turno NOCHE (estaba sumada a la hoja de Tobias del turno dia).',
       'TURNO TRABAJO CON NORMALIDAD... TERMINAR PALET Y CAMBIAR A 50X70X20X21 (MR. TRAPO) | Nota: verificada con la foto: turno noche.'),
      ('f67530b7-4240-4cbe-87c3-067b65b74043'::uuid,
       'Turno trabajado con Total Normalidad, Buen Funcionamiento de maquina | ⚠ REVISAR: verificada con la foto: turno DIA (la IA habia leido noche) y 8 bobinas (la 10-235 no existe, era la 10-285 leida dos veces). La bobina 10-243 tiene un numero escrito encima: se tomo 47.450 kg, confirmar con el papel.',
       'Turno trabajado con Total Normalidad, Buen Funcionamiento de maquina | Nota: verificada con la foto: turno dia, 8 bobinas.'),
      ('91904649-9a16-4f18-abd9-508a20e72cb0'::uuid,
       'TURNO TRABAJADO con total normalidad | ⚠ REVISAR: Bultos leido como 1106 kg / 250 bultos / 6.000 rollos: no es posible, se dejo vacio',
       'TURNO TRABAJADO con total normalidad'),
      ('29c3d260-2d7c-459a-81e2-64f959810b08'::uuid,
       'BUEN FUNCIONAMIENTO DE LA MAQUINA. | ⚠ REVISAR: Bultos leido como 126 BULTOS 80x110x10 / 200 BULTOS 60x80x10 DR PACK: ',
       'BUEN FUNCIONAMIENTO DE LA MAQUINA.'),
      ('7f02a79e-8222-49b4-9881-9f37c62009d0'::uuid,
       'TURNO TRABAJADO CON NORMALIDAD ... BUEN FUNCIONAMIENTO DE LA MAQUINA ... SEGUIMOS CON OTRO PALET DE 50X70 | ⚠ REVISAR: La fecha tiene mas de 60 dias (2026-02-19): verificar',
       'TURNO TRABAJADO CON NORMALIDAD ... BUEN FUNCIONAMIENTO DE LA MAQUINA ... SEGUIMOS CON OTRO PALET DE 50X70')
    ) as n(id, vieja, nueva)
   where p.id = n.id and p.observaciones = n.vieja
  returning p.id
)
select 'R6 16/09 dia Emilio: scrap real 7.200 / 12.850' as cambio, (select count(*) from obs_emilio) = 1 as ok
union all select 'R6 15/09 Tobias: turno noche', (select count(*) from tobias_15) = 1
union all select 'Diego 17/09 noche: pasada a Rollera 5', (select count(*) from diego_17) = 1
union all select 'Diego 17/09 noche: bobina 2-24 Mal', (select count(*) from diego_17_bobina) = 1
union all select 'R5 18/09 dia NAZARENO: bobina 2-25 Mal', (select count(*) from nazareno_18) = 1
union all select 'R5 18/09 dia NAZARENO: nota quitada', (select count(*) from nazareno_18_obs) = 1
union all select 'R6 14/09 noche Tobias: nota quitada', (select count(*) from tobias_14_obs) = 1
union all select 'R6 Tobias 6 bobinas: aviso de otro turno quitado', (select count(*) from tobias_18_obs) = 1
union all select 'R5 07/09 Diego: turno dia', (select count(*) from diego_07) = 1
union all select 'R5 07/09 NAZARENO: verificada noche', (select count(*) from nazareno_07) = 1
union all select 'R5 09/09 Juan Dotti: turno dia', (select count(*) from juan_09) = 1
union all select 'R5 09/09 NAZARENO: verificada noche', (select count(*) from nazareno_09) = 1
union all select 'R5 09/09 NAZARENO: bobina 7-44 Mal', (select count(*) from nazareno_09_bobina) = 1
union all select 'Notas ya resueltas limpiadas (9)', (select count(*) from notas_resueltas) = 9;
