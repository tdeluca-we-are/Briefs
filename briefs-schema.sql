-- ═══════════════════════════════════════════════════════════════════════════
-- WE ARE — Briefs de email
--
-- Briefs armados por bloques (estructura + textos + imágenes de referencia)
-- para mandarle al diseñador. Cada brief es de una marca; las marcas son las
-- mismas del semáforo y el calendario (sem_marcas).
--
-- Correr DESPUÉS de semaforo-schema.sql (necesita sem_marcas).
-- Todo con prefijo brf_. Se puede correr más de una vez.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── USUARIOS ────────────────────────────────────────────────────────────────
-- Mismo criterio que el calendario: se autoriza el mail y la cuenta se vincula
-- sola en el primer login. La cuenta se crea en Supabase → Authentication → Users.
--   admin  : ve y edita todo (todas las marcas, accesos, alta de marcas)
--   editor : ve y edita solo los briefs de las marcas que tiene asignadas
--   lector : ve (sin editar) solo los briefs de las marcas asignadas
create table if not exists brf_usuarios (
  id             serial primary key,
  email          text not null,
  nombre         text,
  rol            text not null default 'lector'
                 check (rol in ('admin','editor','lector')),
  activo         boolean not null default true,
  user_id        uuid,
  ultimo_ingreso timestamptz
);
create unique index if not exists brf_usuarios_email_idx on brf_usuarios (lower(email));
create unique index if not exists brf_usuarios_uid_idx   on brf_usuarios (user_id)
  where user_id is not null;

create table if not exists brf_usuario_marcas (
  usuario_id int not null references brf_usuarios(id) on delete cascade,
  marca_id   int not null references sem_marcas(id)   on delete cascade,
  primary key (usuario_id, marca_id)
);

insert into brf_usuarios (email, nombre, rol) values
  ('tdeluca@we-are.com.ar', 'Tomás De Luca', 'admin')
on conflict do nothing;

-- ── CONFIGURACIÓN VISUAL POR MARCA ──────────────────────────────────────────
create table if not exists brf_marca_config (
  marca_id       int primary key references sem_marcas(id) on delete cascade,
  primario       text not null default '#f04e23',   -- botones, cintillos, cupones
  secundario     text not null default '#f1f1ee',   -- footer, fondos
  notas          text,                              -- tipografía, tono, cosas a evitar
  actualizado_at timestamptz not null default now()
);

-- ── BRIEFS ──────────────────────────────────────────────────────────────────
-- doc = {meta:{campana, asunto, preheader, fecha, objetivo}, blocks:[...]}
create table if not exists brf_briefs (
  id              serial primary key,
  marca_id        int  not null references sem_marcas(id) on delete cascade,
  nombre          text not null default '',
  fecha_envio     text,               -- texto libre del brief (dd/mm), para listar
  estado          text not null default 'borrador'
                  check (estado in ('borrador','en_diseno','listo')),
  doc             jsonb not null default '{}'::jsonb,
  creado_por      text,
  creado_at       timestamptz not null default now(),
  actualizado_por text,
  actualizado_at  timestamptz not null default now()
);
create index if not exists brf_briefs_marca_idx on brf_briefs (marca_id, actualizado_at desc);

-- ── PLANTILLAS ──────────────────────────────────────────────────────────────
-- marca_id null = plantilla general (la ven todos; la edita el admin).
create table if not exists brf_plantillas (
  id         serial primary key,
  marca_id   int references sem_marcas(id) on delete cascade,
  nombre     text not null,
  blocks     jsonb not null default '[]'::jsonb,
  creado_por text,
  creado_at  timestamptz not null default now()
);

-- ── IDENTIDAD Y PERMISOS ────────────────────────────────────────────────────
create or replace function brf_email() returns text
  language sql stable security definer set search_path = public, auth as $$
  select lower(email) from auth.users where id = auth.uid()
$$;

create or replace function brf_rol() returns text
  language sql stable security definer set search_path = public as $$
  select rol from brf_usuarios
   where activo and (user_id = auth.uid() or lower(email) = brf_email())
   limit 1
$$;

create or replace function brf_uid() returns int
  language sql stable security definer set search_path = public as $$
  select id from brf_usuarios
   where activo and (user_id = auth.uid() or lower(email) = brf_email())
   limit 1
$$;

create or replace function brf_puede_ver(m int) returns boolean
  language sql stable security definer set search_path = public as $$
  select brf_rol() = 'admin'
      or (brf_rol() is not null and exists (
            select 1 from brf_usuario_marcas um
             where um.usuario_id = brf_uid() and um.marca_id = m))
$$;

create or replace function brf_puede_editar(m int) returns boolean
  language sql stable security definer set search_path = public as $$
  select brf_rol() = 'admin'
      or (brf_rol() = 'editor' and exists (
            select 1 from brf_usuario_marcas um
             where um.usuario_id = brf_uid() and um.marca_id = m))
$$;

create or replace function brf_vincular()
  returns setof brf_usuarios
  language plpgsql security definer set search_path = public as $$
begin
  update brf_usuarios
     set user_id = auth.uid(), ultimo_ingreso = now()
   where activo and lower(email) = brf_email()
     and (user_id is null or user_id = auth.uid());

  return query
    select * from brf_usuarios
     where activo and (user_id = auth.uid() or lower(email) = brf_email())
     limit 1;
end $$;

grant execute on function brf_email(), brf_rol(), brf_uid(),
                          brf_puede_ver(int), brf_puede_editar(int), brf_vincular() to authenticated;

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table brf_usuarios       enable row level security;
alter table brf_usuario_marcas enable row level security;
alter table brf_marca_config   enable row level security;
alter table brf_briefs         enable row level security;
alter table brf_plantillas     enable row level security;

do $$
declare t text;
begin
  foreach t in array array['brf_marca_config','brf_briefs'] loop
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('create policy %I on %I for select to authenticated
                    using (brf_puede_ver(marca_id))', t || '_read', t);
    execute format('drop policy if exists %I on %I', t || '_write', t);
    execute format('create policy %I on %I for all to authenticated
                    using (brf_puede_editar(marca_id)) with check (brf_puede_editar(marca_id))',
                   t || '_write', t);
  end loop;
end $$;

-- Plantillas: las generales las ve cualquiera con acceso y las toca el admin;
-- las de marca, como los briefs.
drop policy if exists brf_plantillas_read on brf_plantillas;
create policy brf_plantillas_read on brf_plantillas for select to authenticated
  using (case when marca_id is null then brf_rol() is not null else brf_puede_ver(marca_id) end);

drop policy if exists brf_plantillas_write on brf_plantillas;
create policy brf_plantillas_write on brf_plantillas for all to authenticated
  using      (case when marca_id is null then brf_rol() = 'admin' else brf_puede_editar(marca_id) end)
  with check (case when marca_id is null then brf_rol() = 'admin' else brf_puede_editar(marca_id) end);

-- Usuarios: cada uno se ve a sí mismo; el admin ve y edita todo.
drop policy if exists brf_usuarios_self on brf_usuarios;
create policy brf_usuarios_self on brf_usuarios for select to authenticated
  using (user_id = auth.uid() or lower(email) = brf_email() or brf_rol() = 'admin');

drop policy if exists brf_usuarios_admin on brf_usuarios;
create policy brf_usuarios_admin on brf_usuarios for all to authenticated
  using (brf_rol() = 'admin') with check (brf_rol() = 'admin');

drop policy if exists brf_um_read on brf_usuario_marcas;
create policy brf_um_read on brf_usuario_marcas for select to authenticated
  using (brf_rol() = 'admin' or usuario_id = brf_uid());

drop policy if exists brf_um_admin on brf_usuario_marcas;
create policy brf_um_admin on brf_usuario_marcas for all to authenticated
  using (brf_rol() = 'admin') with check (brf_rol() = 'admin');

-- Marcas del semáforo: lectura para quien tenga acceso a la marca en Briefs,
-- y alta para el admin de Briefs (la marca nueva aparece también en el
-- semáforo y el calendario). Las políticas se suman con OR: no cambia nada
-- para las otras herramientas.
drop policy if exists sem_marcas_brf_read on sem_marcas;
create policy sem_marcas_brf_read on sem_marcas for select to authenticated
  using (brf_puede_ver(id));

drop policy if exists sem_marcas_brf_insert on sem_marcas;
create policy sem_marcas_brf_insert on sem_marcas for insert to authenticated
  with check (brf_rol() = 'admin');

-- ── IMÁGENES ────────────────────────────────────────────────────────────────
-- Bucket público de lectura (las URLs son aleatorias; así el PNG exportado
-- puede incluirlas). Ruta: <marca_id>/<brief_id>/<archivo>. Sube y borra
-- quien puede editar esa marca.
insert into storage.buckets (id, name, public)
values ('brf-imagenes', 'brf-imagenes', true)
on conflict (id) do update set public = true;

drop policy if exists brf_img_read on storage.objects;
create policy brf_img_read on storage.objects for select to public
  using (bucket_id = 'brf-imagenes');

drop policy if exists brf_img_write on storage.objects;
create policy brf_img_write on storage.objects for insert to authenticated
  with check (bucket_id = 'brf-imagenes'
              and brf_puede_editar(((storage.foldername(name))[1])::int));

drop policy if exists brf_img_delete on storage.objects;
create policy brf_img_delete on storage.objects for delete to authenticated
  using (bucket_id = 'brf-imagenes'
         and brf_puede_editar(((storage.foldername(name))[1])::int));
