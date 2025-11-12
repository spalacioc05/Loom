-- Migración 004: Agregar columna categoria a tbl_libros
-- Ejecutar en Supabase (SQL Editor) o incluir en pipeline de migraciones.
-- Añade una categoría textual para permitir filtrado en frontend.

ALTER TABLE public.tbl_libros
ADD COLUMN IF NOT EXISTS categoria VARCHAR(60) NOT NULL DEFAULT 'General';

-- Crear índice para búsquedas por categoría
CREATE INDEX IF NOT EXISTS idx_libros_categoria ON public.tbl_libros(categoria);

COMMENT ON COLUMN public.tbl_libros.categoria IS 'Categoría principal del libro para clasificación y filtrado';

-- Opcional: Eliminar el DEFAULT después de asignar categorías reales
-- ALTER TABLE public.tbl_libros ALTER COLUMN categoria DROP DEFAULT;