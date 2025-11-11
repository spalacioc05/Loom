-- Script para ejecutar todas las migraciones en orden
-- Ejecutar este archivo en tu base de datos de Supabase

-- ============================================
-- MIGRACIÓN 000: Tabla de Usuarios
-- ============================================
\echo '📝 Ejecutando migración 000_usuarios.sql...'

-- Agregar columna firebase_uid si no existe (para usuarios existentes)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'tbl_usuarios' 
    AND column_name = 'firebase_uid'
  ) THEN
    ALTER TABLE public.tbl_usuarios ADD COLUMN firebase_uid TEXT NULL;
    CREATE INDEX idx_usuarios_firebase_uid ON public.tbl_usuarios(firebase_uid);
    COMMENT ON COLUMN public.tbl_usuarios.firebase_uid IS 'UID único proporcionado por Firebase Auth';
  END IF;
END $$;

\echo '✅ Migración 000_usuarios.sql completada'

-- ============================================
-- MIGRACIÓN 002: Biblioteca de Usuarios
-- ============================================
\echo '📝 Ejecutando migración 002_user_library.sql...'

CREATE TABLE IF NOT EXISTS public.tbl_libros_x_usuarios (
  id_usuario BIGINT NOT NULL REFERENCES public.tbl_usuarios(id_usuario) ON DELETE CASCADE,
  id_libro BIGINT NOT NULL REFERENCES public.tbl_libros(id_libro) ON DELETE CASCADE,
  fecha_ultima_lectura TIMESTAMP WITHOUT TIME ZONE NULL,
  progreso NUMERIC(5, 2) DEFAULT 0.0,
  tiempo_escucha INTEGER DEFAULT 0,
  CONSTRAINT tbl_libros_x_usuarios_pkey PRIMARY KEY (id_usuario, id_libro)
) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_usuario ON public.tbl_libros_x_usuarios(id_usuario);
CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_libro ON public.tbl_libros_x_usuarios(id_libro);
CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_fecha ON public.tbl_libros_x_usuarios(fecha_ultima_lectura DESC);

COMMENT ON TABLE public.tbl_libros_x_usuarios IS 'Biblioteca personal de cada usuario con sus libros y progreso de lectura';

\echo '✅ Migración 002_user_library.sql completada'

\echo ''
\echo '🎉 ¡Todas las migraciones completadas exitosamente!'
\echo ''
\echo 'Estructura de tbl_usuarios:'
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'tbl_usuarios'
ORDER BY ordinal_position;
