-- Migración: Biblioteca personal de usuarios
-- Tabla intermedia para relación usuario-libros (compatible con esquema Supabase)

CREATE TABLE IF NOT EXISTS public.tbl_libros_x_usuarios (
  id_usuario BIGINT NOT NULL REFERENCES public.tbl_usuarios(id_usuario) ON DELETE CASCADE,
  id_libro BIGINT NOT NULL REFERENCES public.tbl_libros(id_libro) ON DELETE CASCADE,
  fecha_ultima_lectura TIMESTAMP WITHOUT TIME ZONE NULL,
  progreso NUMERIC(5, 2) DEFAULT 0.0, -- Progreso de lectura (0.00 a 100.00%)
  tiempo_escucha INTEGER DEFAULT 0, -- Tiempo de escucha en segundos
  CONSTRAINT tbl_libros_x_usuarios_pkey PRIMARY KEY (id_usuario, id_libro)
) TABLESPACE pg_default;

-- Índice para búsquedas por usuario
CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_usuario ON public.tbl_libros_x_usuarios(id_usuario);

-- Índice para búsquedas por libro
CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_libro ON public.tbl_libros_x_usuarios(id_libro);

-- Índice para ordenar por última lectura
CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_fecha ON public.tbl_libros_x_usuarios(fecha_ultima_lectura DESC);

COMMENT ON TABLE public.tbl_libros_x_usuarios IS 'Biblioteca personal de cada usuario con sus libros y progreso de lectura';
COMMENT ON COLUMN public.tbl_libros_x_usuarios.id_usuario IS 'Referencia al ID del usuario en tbl_usuarios';
COMMENT ON COLUMN public.tbl_libros_x_usuarios.id_libro IS 'Referencia al ID del libro en tbl_libros';
COMMENT ON COLUMN public.tbl_libros_x_usuarios.progreso IS 'Porcentaje de progreso de lectura (0.00 a 100.00)';
COMMENT ON COLUMN public.tbl_libros_x_usuarios.tiempo_escucha IS 'Tiempo total de escucha en segundos';
