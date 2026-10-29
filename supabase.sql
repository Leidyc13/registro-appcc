-- =====================================================================
-- Registro APPCC · Esquema de base de datos para Supabase
-- Ejecutar una sola vez en: Supabase > SQL Editor > New query > Run
-- Cada obrador ve únicamente sus propios datos (Row Level Security).
-- Los registros APPCC no se pueden editar ni borrar: quedan como evidencia.
-- =====================================================================


-- Fechas y horas en hora de España
alter database postgres set timezone to 'Europe/Madrid';

-- ---------- Tablas ----------
create table public.obradores (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(trim(nombre)) > 0),
  sin_gluten boolean not null default false,
  codigo_invitacion text not null unique default upper(substr(md5(random()::text), 1, 8)),
  created_at timestamptz not null default now()
);

create table public.miembros (
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rol text not null default 'empleado' check (rol in ('admin','empleado')),
  nombre text not null default '',
  iniciales text not null default '' check (length(iniciales) <= 4),
  created_at timestamptz not null default now(),
  primary key (obrador_id, user_id)
);

create table public.equipos (
  id uuid primary key default gen_random_uuid(),
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  nombre text not null,
  min numeric(5,1) not null,
  max numeric(5,1) not null check (max >= min),
  activo boolean not null default true,
  orden int not null default 0
);

create table public.tareas_limpieza (
  id uuid primary key default gen_random_uuid(),
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  zona text not null,
  tarea text not null,
  frecuencia text not null check (frecuencia in ('diaria','semanal')),
  activo boolean not null default true,
  orden int not null default 0
);

create table public.registros_temp (
  id uuid primary key default gen_random_uuid(),
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  equipo_id uuid not null references public.equipos(id),
  valor numeric(5,1) not null,
  fecha date not null default current_date,
  hora time not null,
  accion text not null default '',
  user_id uuid not null default auth.uid() references auth.users(id),
  iniciales text not null default '',
  created_at timestamptz not null default now()
);

create table public.registros_limpieza (
  id uuid primary key default gen_random_uuid(),
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  tarea_id uuid not null references public.tareas_limpieza(id),
  fecha date not null default current_date,
  hora time not null,
  user_id uuid not null default auth.uid() references auth.users(id),
  iniciales text not null default '',
  created_at timestamptz not null default now()
);

create table public.recepciones (
  id uuid primary key default gen_random_uuid(),
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  fecha date not null default current_date,
  proveedor text not null,
  producto text not null,
  lote text not null,
  caducidad date not null,
  temperatura numeric(5,1),
  alergenos text[] not null default '{}',
  estado text not null check (estado in ('aceptado','rechazado')),
  observaciones text not null default '',
  user_id uuid not null default auth.uid() references auth.users(id),
  iniciales text not null default '',
  created_at timestamptz not null default now()
);

create table public.lotes_produccion (
  id uuid primary key default gen_random_uuid(),
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  fecha date not null default current_date,
  producto text not null,
  lote text not null,
  cantidad text not null default '',
  alergenos text[] not null default '{}',
  user_id uuid not null default auth.uid() references auth.users(id),
  iniciales text not null default '',
  created_at timestamptz not null default now(),
  unique (obrador_id, lote)
);

create table public.lote_ingredientes (
  lote_id uuid not null references public.lotes_produccion(id) on delete cascade,
  recepcion_id uuid not null references public.recepciones(id),
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  primary key (lote_id, recepcion_id)
);

create table public.incidencias (
  id uuid primary key default gen_random_uuid(),
  obrador_id uuid not null references public.obradores(id) on delete cascade,
  fecha date not null default current_date,
  tipo text not null,
  descripcion text not null,
  accion text not null default '',
  estado text not null default 'abierta' check (estado in ('abierta','cerrada')),
  user_id uuid not null default auth.uid() references auth.users(id),
  iniciales text not null default '',
  cerrada_por text,
  cerrada_at timestamptz,
  created_at timestamptz not null default now()
);

create index on public.registros_temp (obrador_id, fecha desc);
create index on public.registros_limpieza (obrador_id, fecha desc);
create index on public.recepciones (obrador_id, fecha desc);
create index on public.lotes_produccion (obrador_id, fecha desc);
create index on public.incidencias (obrador_id, estado);
create index on public.miembros (user_id);

-- ---------- Funciones de apoyo ----------
create or replace function public.es_miembro(o uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros where obrador_id = o and user_id = auth.uid());
$$;

create or replace function public.es_admin(o uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros where obrador_id = o and user_id = auth.uid() and rol = 'admin');
$$;

-- Crea un obrador nuevo, hace admin a quien lo crea y carga equipos y tareas habituales.
create or replace function public.crear_obrador(p_nombre text, p_sin_gluten boolean, p_nombre_persona text, p_iniciales text)
returns uuid language plpgsql security definer set search_path = public as $$
declare o uuid;
begin
  if auth.uid() is null then raise exception 'Hay que iniciar sesión'; end if;
  insert into obradores (nombre, sin_gluten) values (trim(p_nombre), p_sin_gluten) returning id into o;
  insert into miembros (obrador_id, user_id, rol, nombre, iniciales)
    values (o, auth.uid(), 'admin', trim(p_nombre_persona), upper(left(trim(p_iniciales), 4)));
  insert into equipos (obrador_id, nombre, min, max, orden) values
    (o, 'Cámara materias primas', 0, 4, 1),
    (o, 'Cámara producto terminado', 0, 4, 2),
    (o, 'Congelador', -25, -18, 3),
    (o, 'Vitrina de venta', 0, 6, 4);
  insert into tareas_limpieza (obrador_id, zona, tarea, frecuencia, orden) values
    (o, 'Obrador', 'Mesas y superficies de trabajo', 'diaria', 1),
    (o, 'Obrador', 'Suelos y desagües', 'diaria', 2),
    (o, 'Utensilios', 'Batidoras, moldes y bandejas', 'diaria', 3),
    (o, 'Aseos y vestuario', 'Lavamanos, jabón y papel', 'diaria', 4),
    (o, 'Cámaras', 'Interior de cámaras y juntas de puertas', 'semanal', 5),
    (o, 'Hornos', 'Interior del horno y bandejas', 'semanal', 6);
  return o;
end $$;

-- Une al usuario actual a un obrador con su código de invitación.
create or replace function public.unirse_obrador(p_codigo text, p_nombre_persona text, p_iniciales text)
returns uuid language plpgsql security definer set search_path = public as $$
declare o uuid;
begin
  if auth.uid() is null then raise exception 'Hay que iniciar sesión'; end if;
  select id into o from obradores where codigo_invitacion = upper(trim(p_codigo));
  if o is null then raise exception 'Código de invitación no válido'; end if;
  insert into miembros (obrador_id, user_id, rol, nombre, iniciales)
    values (o, auth.uid(), 'empleado', trim(p_nombre_persona), upper(left(trim(p_iniciales), 4)))
    on conflict (obrador_id, user_id) do nothing;
  return o;
end $$;

-- El admin genera un código nuevo (invalida el anterior).
create or replace function public.nuevo_codigo(p_obrador uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not es_admin(p_obrador) then raise exception 'Solo el administrador puede cambiar el código'; end if;
  c := upper(substr(md5(random()::text), 1, 8));
  update obradores set codigo_invitacion = c where id = p_obrador;
  return c;
end $$;

-- Cierra una incidencia dejando constancia de quién y cuándo.
create or replace function public.cerrar_incidencia(p_id uuid, p_iniciales text) returns void
language plpgsql security definer set search_path = public as $$
declare o uuid;
begin
  select obrador_id into o from incidencias where id = p_id;
  if o is null or not es_miembro(o) then raise exception 'Incidencia no encontrada'; end if;
  update incidencias set estado = 'cerrada', cerrada_por = upper(left(p_iniciales, 4)), cerrada_at = now()
   where id = p_id and estado = 'abierta';
end $$;

-- Un ingrediente solo puede enlazarse a un lote del mismo obrador.
create or replace function public.check_ingrediente() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from lotes_produccion where id = new.lote_id and obrador_id = new.obrador_id)
     or not exists (select 1 from recepciones where id = new.recepcion_id and obrador_id = new.obrador_id) then
    raise exception 'Lote o ingrediente de otro obrador';
  end if;
  return new;
end $$;
create trigger t_check_ingrediente before insert on public.lote_ingredientes
  for each row execute function public.check_ingrediente();

-- El autor de cada registro es siempre quien ha iniciado sesión.
create or replace function public.fijar_autor() returns trigger
language plpgsql as $$
begin
  new.user_id := auth.uid();
  return new;
end $$;
create trigger t_autor before insert on public.registros_temp for each row execute function public.fijar_autor();
create trigger t_autor before insert on public.registros_limpieza for each row execute function public.fijar_autor();
create trigger t_autor before insert on public.recepciones for each row execute function public.fijar_autor();
create trigger t_autor before insert on public.lotes_produccion for each row execute function public.fijar_autor();
create trigger t_autor before insert on public.incidencias for each row execute function public.fijar_autor();

-- ---------- Seguridad por filas ----------
alter table public.obradores enable row level security;
alter table public.miembros enable row level security;
alter table public.equipos enable row level security;
alter table public.tareas_limpieza enable row level security;
alter table public.registros_temp enable row level security;
alter table public.registros_limpieza enable row level security;
alter table public.recepciones enable row level security;
alter table public.lotes_produccion enable row level security;
alter table public.lote_ingredientes enable row level security;
alter table public.incidencias enable row level security;

-- Obrador: los miembros lo ven; el admin cambia nombre y opción sin gluten.
create policy ver on public.obradores for select using (es_miembro(id));
create policy editar on public.obradores for update using (es_admin(id)) with check (es_admin(id));

-- Miembros: se ven entre ellos; cada uno edita sus iniciales; el admin quita gente.
create policy ver on public.miembros for select using (es_miembro(obrador_id));
create policy quitar on public.miembros for delete using (es_admin(obrador_id) and user_id <> auth.uid());

-- Configuración (equipos y tareas): todos la ven, solo el admin la cambia.
create policy ver on public.equipos for select using (es_miembro(obrador_id));
create policy crear on public.equipos for insert with check (es_admin(obrador_id));
create policy editar on public.equipos for update using (es_admin(obrador_id)) with check (es_admin(obrador_id));
create policy ver on public.tareas_limpieza for select using (es_miembro(obrador_id));
create policy crear on public.tareas_limpieza for insert with check (es_admin(obrador_id));
create policy editar on public.tareas_limpieza for update using (es_admin(obrador_id)) with check (es_admin(obrador_id));

-- Registros: los miembros los ven y añaden; nadie los edita ni los borra.
create policy ver on public.registros_temp for select using (es_miembro(obrador_id));
create policy crear on public.registros_temp for insert with check (es_miembro(obrador_id));
create policy ver on public.registros_limpieza for select using (es_miembro(obrador_id));
create policy crear on public.registros_limpieza for insert with check (es_miembro(obrador_id));
create policy ver on public.recepciones for select using (es_miembro(obrador_id));
create policy crear on public.recepciones for insert with check (es_miembro(obrador_id));
create policy ver on public.lotes_produccion for select using (es_miembro(obrador_id));
create policy crear on public.lotes_produccion for insert with check (es_miembro(obrador_id));
create policy ver on public.lote_ingredientes for select using (es_miembro(obrador_id));
create policy crear on public.lote_ingredientes for insert with check (es_miembro(obrador_id));
create policy ver on public.incidencias for select using (es_miembro(obrador_id));
create policy crear on public.incidencias for insert with check (es_miembro(obrador_id));
-- (las incidencias se cierran solo con la función cerrar_incidencia)

-- Crea un lote de producción con sus ingredientes en un solo paso.
-- Los alérgenos del lote se calculan a partir de los ingredientes.
create or replace function public.crear_lote(p_obrador uuid, p_producto text, p_cantidad text, p_prefijo text, p_ingredientes uuid[], p_iniciales text)
returns text language plpgsql security definer set search_path = public as $$
declare base text; codigo text; n int := 1; l uuid; al text[];
begin
  if not es_miembro(p_obrador) then raise exception 'Sin acceso a este obrador'; end if;
  if coalesce(array_length(p_ingredientes, 1), 0) = 0 then raise exception 'Marca al menos un lote de materia prima'; end if;
  if exists (select 1 from unnest(p_ingredientes) i where not exists
      (select 1 from recepciones r where r.id = i and r.obrador_id = p_obrador and r.estado = 'aceptado')) then
    raise exception 'Algún ingrediente no es válido';
  end if;
  select coalesce(array_agg(distinct a order by a), '{}') into al
    from recepciones r, unnest(r.alergenos) a where r.id = any(p_ingredientes);
  base := upper(coalesce(nullif(regexp_replace(trim(p_prefijo), '[^A-Za-z0-9]', '', 'g'), ''), 'LT')) || '-' || to_char(current_date, 'YYMMDD');
  codigo := base;
  while exists (select 1 from lotes_produccion where obrador_id = p_obrador and lote = codigo) loop
    n := n + 1; codigo := base || '-' || n;
  end loop;
  insert into lotes_produccion (obrador_id, producto, lote, cantidad, alergenos, iniciales, user_id)
    values (p_obrador, trim(p_producto), codigo, trim(p_cantidad), al, upper(left(p_iniciales, 4)), auth.uid()) returning id into l;
  insert into lote_ingredientes (lote_id, recepcion_id, obrador_id)
    select l, i, p_obrador from unnest(p_ingredientes) i;
  return codigo;
end $$;

-- Cada persona cambia su propio nombre e iniciales (no su rol).
create or replace function public.actualizar_perfil(p_obrador uuid, p_nombre text, p_iniciales text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update miembros set nombre = trim(p_nombre), iniciales = upper(left(trim(p_iniciales), 4))
   where obrador_id = p_obrador and user_id = auth.uid();
end $$;

revoke execute on function public.crear_obrador(text, boolean, text, text) from public, anon;
revoke execute on function public.unirse_obrador(text, text, text) from public, anon;
revoke execute on function public.nuevo_codigo(uuid) from public, anon;
revoke execute on function public.cerrar_incidencia(uuid, text) from public, anon;
revoke execute on function public.actualizar_perfil(uuid, text, text) from public, anon;
revoke execute on function public.crear_lote(uuid, text, text, text, uuid[], text) from public, anon;
grant execute on function public.crear_obrador(text, boolean, text, text) to authenticated;
grant execute on function public.unirse_obrador(text, text, text) to authenticated;
grant execute on function public.nuevo_codigo(uuid) to authenticated;
grant execute on function public.cerrar_incidencia(uuid, text) to authenticated;
grant execute on function public.actualizar_perfil(uuid, text, text) to authenticated;
grant execute on function public.crear_lote(uuid, text, text, text, uuid[], text) to authenticated;
