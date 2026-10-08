-- ═══════════════════════════════════════════════════════════════════════════
-- WE ARE — Briefs de email · v2 (08/10/2026)
--   · Logo por marca (brf_marca_config.logo_url)
--   · Biblioteca de plantillas: descripción, propuestas de editores para que
--     el admin las apruebe como generales, y quién/cuándo las editó
--   · Imágenes de plantillas generales (carpeta 'general' del bucket)
--
-- Correr DESPUÉS de briefs-schema.sql. Se puede correr más de una vez.
-- ═══════════════════════════════════════════════════════════════════════════

alter table brf_marca_config add column if not exists logo_url text;

alter table brf_plantillas add column if not exists descripcion     text;
alter table brf_plantillas add column if not exists propuesta       text;   -- null | pendiente | aprobada | rechazada
alter table brf_plantillas add column if not exists propuesta_por   text;
alter table brf_plantillas add column if not exists propuesta_at    timestamptz;
alter table brf_plantillas add column if not exists revisada_por    text;
alter table brf_plantillas add column if not exists origen_id       int references brf_plantillas(id) on delete set null;
alter table brf_plantillas add column if not exists actualizado_por text;
alter table brf_plantillas add column if not exists actualizado_at  timestamptz not null default now();

alter table brf_plantillas drop constraint if exists brf_plantillas_propuesta_check;
alter table brf_plantillas add constraint brf_plantillas_propuesta_check
  check (propuesta is null or propuesta in ('pendiente','aprobada','rechazada'));

-- Imágenes: <marca_id>/... para briefs y plantillas de marca (quien edita la marca)
-- y general/... para plantillas generales (solo admin).
drop policy if exists brf_img_write on storage.objects;
create policy brf_img_write on storage.objects for insert to authenticated
  with check (bucket_id = 'brf-imagenes' and
    case when (storage.foldername(name))[1] = 'general' then brf_rol() = 'admin'
         else brf_puede_editar(((storage.foldername(name))[1])::int) end);

drop policy if exists brf_img_delete on storage.objects;
create policy brf_img_delete on storage.objects for delete to authenticated
  using (bucket_id = 'brf-imagenes' and
    case when (storage.foldername(name))[1] = 'general' then brf_rol() = 'admin'
         else brf_puede_editar(((storage.foldername(name))[1])::int) end);
