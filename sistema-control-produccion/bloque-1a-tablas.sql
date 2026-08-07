-- ============================================================
-- BLOQUE 1a: TABLAS (ejecutar primero)
-- ============================================================

create extension if not exists pgcrypto;

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

select 'BLOQUE 1a OK: tablas creadas' as resultado;
