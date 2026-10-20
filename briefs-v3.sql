-- ═══════════════════════════════════════════════════════════════════════════
-- WE ARE — Briefs de email · v3 (20/10/2026)
--   · Bloques guardados para reutilizar (un bloque suelto o una fila entera)
--     marca_id null = general (lo ven todos, lo guarda/borra el admin);
--     con marca = como los briefs (lo ve quien ve la marca, lo toca quien la edita)
--
-- Correr DESPUÉS de briefs-schema.sql y briefs-v2.sql. Se puede correr más de una vez.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists brf_bloques (
  id         serial primary key,
  marca_id   int references sem_marcas(id) on delete cascade,
  nombre     text not null,
  bloque     jsonb not null,          -- el bloque tal cual (si es una fila, con sus columnas)
  creado_por text,
  creado_at  timestamptz not null default now()
);

alter table brf_bloques enable row level security;

drop policy if exists brf_bloques_read on brf_bloques;
create policy brf_bloques_read on brf_bloques for select to authenticated
  using (case when marca_id is null then brf_rol() is not null else brf_puede_ver(marca_id) end);

drop policy if exists brf_bloques_write on brf_bloques;
create policy brf_bloques_write on brf_bloques for all to authenticated
  using      (case when marca_id is null then brf_rol() = 'admin' else brf_puede_editar(marca_id) end)
  with check (case when marca_id is null then brf_rol() = 'admin' else brf_puede_editar(marca_id) end);
