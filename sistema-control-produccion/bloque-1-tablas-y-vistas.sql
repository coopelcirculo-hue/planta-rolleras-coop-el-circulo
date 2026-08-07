-- ============================================================
-- BLOQUE 1 de 3: TABLAS Y VISTAS
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- TABLAS ----------

create table if not exists empresas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  creado_en timestamptz not null default now()
);

create table if not exists plantas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  nombre text not null,
  unique (empresa_id, nombre)
);

create table if not exists maquinas (
  id uuid primary key default gen_random_uuid(),
  planta_id uuid not null references plantas(id) on delete cascade,
  codigo text not null,
  nombre text,
  activa boolean not null default true,
  unique (planta_id, codigo)
);

create table if not exists operarios (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  nombre text not null,
  iniciales text,
  activo boolean not null default true,
  unique (empresa_id, nombre)
);

create table if not exists defectos (
  id serial primary key,
  nombre text not null unique
);

-- Un parte de produccion = una hoja de control (maquina + fecha + turno)
create table if not exists producciones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  planta_id uuid not null references plantas(id),
  maquina_id uuid not null references maquinas(id),
  operario_id uuid references operarios(id),
  fecha date not null,
  turno text not null check (turno in ('dia','noche')),
  medida text,
  filas int,
  bultos int,
  observaciones text,
  origen text,
  creado_en timestamptz not null default now(),
  unique (maquina_id, fecha, turno)
);

-- Cada bobina es un registro independiente
create table if not exists bobinas (
  id uuid primary key default gen_random_uuid(),
  produccion_id uuid not null references producciones(id) on delete cascade,
  n_bobina text not null,
  peso numeric,
  iniciales text,
  operario_id uuid references operarios(id),
  estado text check (estado in ('BIEN','MAL')),
  unique (produccion_id, n_bobina)
);

create table if not exists bobina_defectos (
  bobina_id uuid not null references bobinas(id) on delete cascade,
  defecto_id int not null references defectos(id),
  detalle text,
  primary key (bobina_id, defecto_id)
);

create table if not exists scrap (
  id uuid primary key default gen_random_uuid(),
  produccion_id uuid not null unique references producciones(id) on delete cascade,
  empalme numeric not null default 0,
  rollo numeric not null default 0
);

create table if not exists historial (
  id bigint generated always as identity primary key,
  empresa_id uuid references empresas(id),
  evento text not null,
  detalle jsonb,
  creado_en timestamptz not null default now()
);

-- ---------- VISTAS (estadisticas siempre en tiempo real) ----------

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
  p.id as produccion_id
from bobinas b
join producciones p on p.id = b.produccion_id
join empresas e on e.id = p.empresa_id
join plantas pl on pl.id = p.planta_id
join maquinas m on m.id = p.maquina_id
left join operarios op on op.id = p.operario_id
left join operarios ob on ob.id = b.operario_id;

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
  coalesce(s.rollo,0) as scrap_rollo
from producciones p
join empresas e on e.id = p.empresa_id
join plantas pl on pl.id = p.planta_id
join maquinas m on m.id = p.maquina_id
left join operarios o on o.id = p.operario_id
left join scrap s on s.produccion_id = p.id;

create or replace view v_produccion_diaria as
select empresa_id, empresa, fecha,
  sum(bobinas) as bobinas, sum(kilos) as kilos,
  case when sum(bobinas) > 0 then round(sum(kilos)/sum(bobinas),1) end as peso_promedio,
  sum(bien) as bien, sum(mal) as mal, sum(bultos) as bultos,
  sum(scrap_empalme) as scrap_empalme, sum(scrap_rollo) as scrap_rollo,
  case when sum(kilos) > 0 then round(100*(sum(scrap_empalme)+sum(scrap_rollo))/sum(kilos),2) end as scrap_pct
from v_producciones
group by empresa_id, empresa, fecha;

create or replace view v_produccion_semanal as
select empresa_id, empresa, date_trunc('week', fecha)::date as semana,
  sum(bobinas) as bobinas, sum(kilos) as kilos,
  case when sum(bobinas) > 0 then round(sum(kilos)/sum(bobinas),1) end as peso_promedio,
  sum(bien) as bien, sum(mal) as mal, sum(bultos) as bultos,
  sum(scrap_empalme) as scrap_empalme, sum(scrap_rollo) as scrap_rollo,
  case when sum(kilos) > 0 then round(100*(sum(scrap_empalme)+sum(scrap_rollo))/sum(kilos),2) end as scrap_pct
from v_producciones
group by empresa_id, empresa, date_trunc('week', fecha);

create or replace view v_produccion_mensual as
select empresa_id, empresa, date_trunc('month', fecha)::date as mes,
  sum(bobinas) as bobinas, sum(kilos) as kilos,
  case when sum(bobinas) > 0 then round(sum(kilos)/sum(bobinas),1) end as peso_promedio,
  sum(bien) as bien, sum(mal) as mal, sum(bultos) as bultos,
  sum(scrap_empalme) as scrap_empalme, sum(scrap_rollo) as scrap_rollo,
  case when sum(kilos) > 0 then round(100*(sum(scrap_empalme)+sum(scrap_rollo))/sum(kilos),2) end as scrap_pct
from v_producciones
group by empresa_id, empresa, date_trunc('month', fecha);

create or replace view v_por_maquina as
select empresa_id, empresa, maquina,
  sum(bobinas) as bobinas, sum(kilos) as kilos, sum(bien) as bien, sum(mal) as mal,
  sum(scrap_empalme) as scrap_empalme, sum(scrap_rollo) as scrap_rollo,
  case when sum(kilos) > 0 then round(100*(sum(scrap_empalme)+sum(scrap_rollo))/sum(kilos),2) end as scrap_pct
from v_producciones
group by empresa_id, empresa, maquina;

create or replace view v_por_operario as
select p.empresa_id, empresa, coalesce(operario_bobina,'S/D') as operario,
  count(*) as bobinas, coalesce(sum(peso),0) as kilos,
  count(*) filter (where estado = 'BIEN') as bien,
  count(*) filter (where estado = 'MAL') as mal
from v_bobinas p
group by p.empresa_id, empresa, coalesce(operario_bobina,'S/D');

create or replace view v_por_turno as
select empresa_id, empresa, turno,
  sum(bobinas) as bobinas, sum(kilos) as kilos, sum(bien) as bien, sum(mal) as mal,
  sum(scrap_empalme) as scrap_empalme, sum(scrap_rollo) as scrap_rollo
from v_producciones
group by empresa_id, empresa, turno;

create or replace view v_defectos as
select p.empresa_id, e.nombre as empresa, p.fecha, m.codigo as maquina,
  coalesce(d.nombre, bd.detalle, 'sin detalle') as defecto, count(*) as cantidad
from bobina_defectos bd
left join defectos d on d.id = bd.defecto_id
join bobinas b on b.id = bd.bobina_id
join producciones p on p.id = b.produccion_id
join empresas e on e.id = p.empresa_id
join maquinas m on m.id = p.maquina_id
group by p.empresa_id, e.nombre, p.fecha, m.codigo, coalesce(d.nombre, bd.detalle, 'sin detalle');

create or replace view v_scrap as
select p.empresa_id, e.nombre as empresa, m.codigo as maquina, p.fecha, p.turno,
  s.empalme, s.rollo, s.empalme + s.rollo as total
from scrap s
join producciones p on p.id = s.produccion_id
join empresas e on e.id = p.empresa_id
join maquinas m on m.id = p.maquina_id;
