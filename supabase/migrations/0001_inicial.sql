-- 0001_inicial.sql
-- Esquema inicial de MAGXOR INMUEBLES (versión lite)

create extension if not exists unaccent;
create extension if not exists pg_trgm;

-- ============================================================
-- Tipos
-- ============================================================
create type tipo_operacion as enum ('venta', 'alquiler_largo', 'alquiler_temporario');
create type estado_publicacion as enum ('disponible', 'reservado', 'alquilado', 'vendido', 'pausado');
create type estado_cuenta as enum ('pendiente_pago', 'activa', 'atrasada', 'suspendida', 'cancelada');

-- ============================================================
-- Países (catálogo: la plataforma decide cuáles existen)
-- ============================================================
create table paises (
  id smallint generated always as identity primary key,
  iso char(2) not null unique,
  nombre text not null,
  habilitado boolean not null default false
);

insert into paises (iso, nombre, habilitado) values ('AR', 'Argentina', true);

-- ============================================================
-- Normalización para comparar nombres ("Río Cuarto" = "rio cuarto")
-- ============================================================
create or replace function normalizar_texto(t text) returns text
language sql immutable as $$
  select lower(regexp_replace(trim(unaccent('unaccent', t)), '\s+', ' ', 'g'))
$$;

-- ============================================================
-- Provincias y localidades (las cargan las inmobiliarias)
-- ============================================================
create table provincias (
  id int generated always as identity primary key,
  pais_id smallint not null references paises(id),
  nombre text not null check (length(trim(nombre)) between 2 and 80),
  nombre_normalizado text generated always as (normalizar_texto(nombre)) stored,
  created_at timestamptz not null default now(),
  unique (pais_id, nombre_normalizado)
);

create table localidades (
  id int generated always as identity primary key,
  provincia_id int not null references provincias(id),
  nombre text not null check (length(trim(nombre)) between 2 and 80),
  nombre_normalizado text generated always as (normalizar_texto(nombre)) stored,
  created_at timestamptz not null default now(),
  unique (provincia_id, nombre_normalizado)
);

create index provincias_nombre_trgm on provincias using gin (nombre_normalizado gin_trgm_ops);
create index localidades_nombre_trgm on localidades using gin (nombre_normalizado gin_trgm_ops);

create or replace function obtener_o_crear_provincia(p_pais smallint, p_nombre text)
returns int language plpgsql as $$
declare v_id int;
begin
  insert into provincias (pais_id, nombre) values (p_pais, trim(p_nombre))
  on conflict (pais_id, nombre_normalizado) do update set nombre = provincias.nombre
  returning id into v_id;
  return v_id;
end $$;

create or replace function obtener_o_crear_localidad(p_provincia int, p_nombre text)
returns int language plpgsql as $$
declare v_id int;
begin
  insert into localidades (provincia_id, nombre) values (p_provincia, trim(p_nombre))
  on conflict (provincia_id, nombre_normalizado) do update set nombre = localidades.nombre
  returning id into v_id;
  return v_id;
end $$;

create or replace function buscar_localidades_similares(p_provincia int, p_texto text)
returns table (id int, nombre text, similitud real)
language sql stable as $$
  select l.id, l.nombre, similarity(l.nombre_normalizado, normalizar_texto(p_texto))
  from localidades l
  where l.provincia_id = p_provincia
    and similarity(l.nombre_normalizado, normalizar_texto(p_texto)) > 0.3
  order by 3 desc
  limit 8
$$;

-- ============================================================
-- Cuentas (el titular que paga)
-- ============================================================
create table cuentas (
  id bigint generated always as identity primary key,
  nombre text not null,
  email_titular text not null,
  estado estado_cuenta not null default 'pendiente_pago',
  bloqueo_manual boolean not null default false,
  numero_fundadora smallint unique check (numero_fundadora between 1 and 20),
  monto_mensual_ars numeric(14,2),
  created_at timestamptz not null default now()
);

create table cuenta_paises (
  cuenta_id bigint not null references cuentas(id) on delete cascade,
  pais_id smallint not null references paises(id),
  primary key (cuenta_id, pais_id)
);

-- ============================================================
-- Inmobiliarias y sedes
-- ============================================================
create table inmobiliarias (
  id bigint generated always as identity primary key,
  cuenta_id bigint not null references cuentas(id),
  nombre text not null,
  subdominio text not null unique
    check (subdominio ~ '^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$'),
  check (subdominio not in ('www','admin','api','app','panel','mail','inmuebles','ftp','static','cdn','soporte','ayuda')),
  email text not null,
  descripcion text,
  logo_url text,
  color_primario text,
  activa boolean not null default true,
  created_at timestamptz not null default now()
);

create index inmobiliarias_cuenta on inmobiliarias (cuenta_id);

create table sedes (
  id bigint generated always as identity primary key,
  inmobiliaria_id bigint not null references inmobiliarias(id),
  nombre text not null,
  localidad_id int not null references localidades(id),
  direccion text,
  telefono text,
  whatsapp text,
  es_principal boolean not null default false
);

create index sedes_inmobiliaria on sedes (inmobiliaria_id);
create unique index sedes_principal_unica on sedes (inmobiliaria_id) where es_principal;

-- ============================================================
-- Usuarios (vinculados a Supabase Auth)
-- ============================================================
create table usuarios (
  id bigint generated always as identity primary key,
  auth_user_id uuid unique references auth.users(id) on delete cascade,
  rol text not null check (rol in ('superadmin', 'titular', 'admin', 'agente')),
  cuenta_id bigint references cuentas(id),
  inmobiliaria_id bigint references inmobiliarias(id),
  sede_id bigint references sedes(id),
  nombre text not null,
  email text not null,
  debe_cambiar_password boolean not null default false,
  created_at timestamptz not null default now(),
  check (rol = 'superadmin' or cuenta_id is not null)
);

-- Un solo superadmin en toda la plataforma
create unique index usuarios_unico_superadmin on usuarios (rol) where rol = 'superadmin';
create index usuarios_cuenta on usuarios (cuenta_id);
create index usuarios_inmobiliaria on usuarios (inmobiliaria_id);

-- ============================================================
-- Pagos (registro manual en el MVP)
-- ============================================================
create table pagos (
  id bigint generated always as identity primary key,
  cuenta_id bigint not null references cuentas(id),
  periodo date not null,
  monto_ars numeric(14,2) not null check (monto_ars >= 0),
  metodo text not null default 'mp_link' check (metodo in ('mp_link', 'transferencia', 'otro')),
  comprobante text,
  pagado_at timestamptz,
  registrado_por bigint references usuarios(id),
  created_at timestamptz not null default now()
);

create unique index pagos_un_pago_por_periodo on pagos (cuenta_id, periodo);

-- ============================================================
-- Tipos de inmueble y etiquetas de operación
-- ============================================================
create table tipos_inmueble (
  id smallint generated always as identity primary key,
  clave text not null unique,
  nombre text not null,
  orden smallint not null default 0
);

insert into tipos_inmueble (clave, nombre, orden) values
  ('casa', 'Casa', 1),
  ('departamento', 'Departamento', 2),
  ('ph', 'PH', 3),
  ('lote', 'Lote', 4),
  ('galpon', 'Galpón', 5),
  ('local', 'Local', 6),
  ('oficina', 'Oficina', 7);

create table operacion_etiquetas (
  operacion tipo_operacion not null,
  audiencia text not null check (audiencia in ('publico', 'inmobiliaria')),
  etiqueta text not null,
  primary key (operacion, audiencia)
);

insert into operacion_etiquetas values
  ('venta', 'publico', 'Compra'),
  ('venta', 'inmobiliaria', 'Venta'),
  ('alquiler_largo', 'publico', 'Alquiler'),
  ('alquiler_largo', 'inmobiliaria', 'Alquiler'),
  ('alquiler_temporario', 'publico', 'Alquiler temporario'),
  ('alquiler_temporario', 'inmobiliaria', 'Alquiler temporario');

-- ============================================================
-- Inmuebles
-- ============================================================
create table inmuebles (
  id bigint generated always as identity primary key,
  inmobiliaria_id bigint not null references inmobiliarias(id),
  sede_id bigint not null references sedes(id),
  agente_id bigint references usuarios(id),
  tipo_id smallint not null references tipos_inmueble(id),
  localidad_id int not null references localidades(id),
  direccion text not null,
  titulo text not null,
  descripcion text,
  superficie_total numeric(10,2),
  superficie_cubierta numeric(10,2),
  ambientes smallint,
  dormitorios smallint,
  banos smallint,
  antiguedad smallint,
  estado_conservacion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index inmuebles_busqueda on inmuebles (inmobiliaria_id, localidad_id, tipo_id);
create index inmuebles_sede on inmuebles (sede_id);
create index inmuebles_agente on inmuebles (agente_id);

create table fotos (
  id bigint generated always as identity primary key,
  inmueble_id bigint not null references inmuebles(id) on delete cascade,
  url text not null,
  orden smallint not null default 0,
  es_principal boolean not null default false
);

create unique index fotos_una_principal on fotos (inmueble_id) where es_principal;

-- ============================================================
-- Publicaciones (MVP: venta y alquiler largo)
-- ============================================================
create table publicaciones (
  id bigint generated always as identity primary key,
  inmueble_id bigint not null references inmuebles(id) on delete cascade,
  inmobiliaria_id bigint not null references inmobiliarias(id),
  operacion tipo_operacion not null check (operacion in ('venta', 'alquiler_largo')),
  precio numeric(14,2) not null check (precio >= 0),
  moneda char(3) not null default 'ARS' check (moneda in ('ARS', 'USD')),
  estado estado_publicacion not null default 'disponible',
  fecha_publicacion timestamptz not null default now()
);

create unique index publicaciones_activa_unica
  on publicaciones (inmueble_id, operacion) where estado = 'disponible';
create index publicaciones_busqueda on publicaciones (operacion, estado, inmobiliaria_id);

create table publicacion_alquiler (
  publicacion_id bigint primary key references publicaciones(id) on delete cascade,
  garantia text,
  expensas_incluidas boolean,
  expensas_monto numeric(14,2),
  plazo_minimo_meses smallint
);

-- ============================================================
-- Características (catálogo con operaciones válidas)
-- ============================================================
create table caracteristicas (
  id smallint generated always as identity primary key,
  clave text not null unique,
  nombre text not null,
  grupo text not null,
  ambito text not null check (ambito in ('inmueble', 'publicacion')),
  operaciones tipo_operacion[] not null check (cardinality(operaciones) > 0),
  orden smallint not null default 0
);

create table inmueble_caracteristicas (
  inmueble_id bigint not null references inmuebles(id) on delete cascade,
  caracteristica_id smallint not null references caracteristicas(id),
  primary key (inmueble_id, caracteristica_id)
);

create table publicacion_caracteristicas (
  publicacion_id bigint not null references publicaciones(id) on delete cascade,
  caracteristica_id smallint not null references caracteristicas(id),
  primary key (publicacion_id, caracteristica_id)
);

insert into caracteristicas (clave, nombre, grupo, ambito, operaciones, orden) values
  ('cochera', 'Cochera', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 1),
  ('pileta', 'Pileta', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 2),
  ('quincho', 'Quincho', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 3),
  ('parrilla', 'Parrilla', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 4),
  ('jardin', 'Jardín', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 5),
  ('patio', 'Patio', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 6),
  ('balcon', 'Balcón', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 7),
  ('terraza', 'Terraza', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 8),
  ('gimnasio', 'Gimnasio', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 9),
  ('sum', 'Salón de usos múltiples', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 10),
  ('ascensor', 'Ascensor', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 11),
  ('bicicletero', 'Espacio para bicicletas', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 12),
  ('aire_acondicionado', 'Aire acondicionado', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 13),
  ('calefaccion', 'Calefacción', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 14),
  ('planta_baja', 'Planta baja', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 15),
  ('movilidad_reducida', 'Apto movilidad reducida', 'comodidades', 'inmueble', '{venta,alquiler_largo}', 16),
  ('portero', 'Portero eléctrico', 'seguridad', 'inmueble', '{venta,alquiler_largo}', 1),
  ('seguridad_24', 'Seguridad 24 hs', 'seguridad', 'inmueble', '{venta,alquiler_largo}', 2),
  ('camaras', 'Cámaras de seguridad', 'seguridad', 'inmueble', '{venta,alquiler_largo}', 3),
  ('alarma', 'Alarma', 'seguridad', 'inmueble', '{venta,alquiler_largo}', 4),
  ('agua_corriente', 'Agua corriente', 'servicios', 'inmueble', '{venta,alquiler_largo}', 1),
  ('cloacas', 'Cloacas', 'servicios', 'inmueble', '{venta,alquiler_largo}', 2),
  ('gas_natural', 'Gas natural', 'servicios', 'inmueble', '{venta,alquiler_largo}', 3),
  ('electricidad_trifasica', 'Electricidad trifásica', 'servicios', 'inmueble', '{venta,alquiler_largo}', 4),
  ('fibra_optica', 'Fibra óptica', 'servicios', 'inmueble', '{venta,alquiler_largo}', 5),
  ('amueblado', 'Amueblado', 'mobiliario', 'inmueble', '{alquiler_largo}', 1),
  ('disponible_ya', 'Disponible inmediatamente', 'condiciones', 'publicacion', '{venta,alquiler_largo}', 1),
  ('libre_ocupantes', 'Libre de ocupantes', 'condiciones', 'publicacion', '{venta}', 2),
  ('financiacion', 'Financiación', 'condiciones', 'publicacion', '{venta}', 3),
  ('acepta_permuta', 'Acepta permuta', 'condiciones', 'publicacion', '{venta}', 4),
  ('apto_credito', 'Apto crédito', 'condiciones', 'publicacion', '{venta}', 5),
  ('expensas_al_dia', 'Expensas al día', 'condiciones', 'publicacion', '{venta}', 6),
  ('uso_comercial', 'Admite uso comercial', 'condiciones', 'publicacion', '{alquiler_largo}', 7),
  ('admite_mascotas', 'Admite mascotas', 'admision', 'publicacion', '{alquiler_largo}', 1),
  ('admite_ninos', 'Admite niños', 'admision', 'publicacion', '{alquiler_largo}', 2),
  ('expensas_incluidas', 'Expensas incluidas', 'incluidos', 'publicacion', '{alquiler_largo}', 1),
  ('luz_incluida', 'Luz incluida', 'incluidos', 'publicacion', '{alquiler_largo}', 2),
  ('gas_incluido', 'Gas incluido', 'incluidos', 'publicacion', '{alquiler_largo}', 3),
  ('agua_incluida', 'Agua incluida', 'incluidos', 'publicacion', '{alquiler_largo}', 4),
  ('internet_incluido', 'Internet incluido', 'incluidos', 'publicacion', '{alquiler_largo}', 5);

-- Impide asignar a una publicación una característica que no corresponde a su operación
create or replace function validar_caracteristica_publicacion() returns trigger
language plpgsql as $$
begin
  if not exists (
    select 1
    from caracteristicas c
    join publicaciones p on p.id = new.publicacion_id
    where c.id = new.caracteristica_id
      and c.ambito = 'publicacion'
      and p.operacion = any(c.operaciones)
  ) then
    raise exception 'La característica no aplica a la operación de esta publicación';
  end if;
  return new;
end $$;

create trigger trg_validar_caracteristica_publicacion
  before insert or update on publicacion_caracteristicas
  for each row execute function validar_caracteristica_publicacion();

-- ============================================================
-- Validar que la localidad pertenezca a un país habilitado en la cuenta
-- (se aplica a sedes e inmuebles)
-- ============================================================
create or replace function validar_pais_habilitado() returns trigger
language plpgsql as $$
declare
  v_pais smallint;
  v_cuenta bigint;
begin
  select pr.pais_id into v_pais
  from localidades l join provincias pr on pr.id = l.provincia_id
  where l.id = new.localidad_id;

  select i.cuenta_id into v_cuenta
  from inmobiliarias i where i.id = new.inmobiliaria_id;

  if not exists (
    select 1 from cuenta_paises
    where cuenta_id = v_cuenta and pais_id = v_pais
  ) then
    raise exception 'El país de la localidad no está habilitado en la cuenta';
  end if;
  return new;
end $$;

create trigger trg_pais_sedes
  before insert or update of localidad_id, inmobiliaria_id on sedes
  for each row execute function validar_pais_habilitado();

create trigger trg_pais_inmuebles
  before insert or update of localidad_id, inmobiliaria_id on inmuebles
  for each row execute function validar_pais_habilitado();

-- ============================================================
-- Fusión de localidades duplicadas (solo superadmin, desde el backend)
-- ============================================================
create or replace function fusionar_localidades(p_origen int, p_destino int)
returns void language plpgsql as $$
begin
  update sedes     set localidad_id = p_destino where localidad_id = p_origen;
  update inmuebles set localidad_id = p_destino where localidad_id = p_origen;
  delete from localidades where id = p_origen;
end $$;

-- ============================================================
-- Auditoría y correos (sin FK hacia cuentas: el registro sobrevive)
-- ============================================================
create table admin_acciones (
  id bigint generated always as identity primary key,
  accion text not null,
  cuenta_id bigint,
  inmobiliaria_id bigint,
  detalle jsonb not null default '{}',
  motivo text not null check (length(motivo) >= 5),
  ejecutado_por bigint not null references usuarios(id),
  created_at timestamptz not null default now()
);

create table correos_salientes (
  id bigint generated always as identity primary key,
  destinatario text not null,
  plantilla text not null,
  datos jsonb not null default '{}',
  dedupe_key text unique,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'enviado', 'error')),
  intentos smallint not null default 0,
  created_at timestamptz not null default now(),
  enviado_at timestamptz
);

-- ============================================================
-- Row Level Security: activada en todas las tablas.
-- Sin políticas, ningún rol de la API pública accede a nada.
-- Las políticas se escriben en la semana 2.
-- ============================================================
alter table paises enable row level security;
alter table provincias enable row level security;
alter table localidades enable row level security;
alter table cuentas enable row level security;
alter table cuenta_paises enable row level security;
alter table inmobiliarias enable row level security;
alter table sedes enable row level security;
alter table usuarios enable row level security;
alter table pagos enable row level security;
alter table tipos_inmueble enable row level security;
alter table operacion_etiquetas enable row level security;
alter table inmuebles enable row level security;
alter table fotos enable row level security;
alter table publicaciones enable row level security;
alter table publicacion_alquiler enable row level security;
alter table caracteristicas enable row level security;
alter table inmueble_caracteristicas enable row level security;
alter table publicacion_caracteristicas enable row level security;
alter table admin_acciones enable row level security;
alter table correos_salientes enable row level security;