-- fix_existing_categorias_table.sql
-- La tabla tbl_categorias existente solo tiene columnas id y created_at.
-- Vamos a renombrarla para no perderla y crear la versión correcta.

ALTER TABLE IF EXISTS public.tbl_categorias RENAME TO tbl_categorias_old_backup_20251112;

CREATE TABLE public.tbl_categorias (
    id_categoria SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- (Re)crear tabla de relación si no existe
CREATE TABLE IF NOT EXISTS public.tbl_libros_x_categorias (
    id_libro INTEGER NOT NULL,
    id_categoria INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_libro, id_categoria),
    FOREIGN KEY (id_libro) REFERENCES public.tbl_libros(id_libro) ON DELETE CASCADE,
    FOREIGN KEY (id_categoria) REFERENCES public.tbl_categorias(id_categoria) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_libros_x_categorias_libro ON public.tbl_libros_x_categorias(id_libro);
CREATE INDEX IF NOT EXISTS idx_libros_x_categorias_categoria ON public.tbl_libros_x_categorias(id_categoria);

-- Poblar catálogo base
INSERT INTO public.tbl_categorias (nombre, descripcion) VALUES
    ('General', 'Categoría general'),
    ('Aventura', 'Acción y aventuras'),
    ('Romance', 'Historias románticas'),
    ('Ciencia Ficción', 'Ficción especulativa'),
    ('Fantasía', 'Magia y mundos imaginarios'),
    ('Misterio', 'Suspenso e investigación'),
    ('Terror', 'Horror y suspenso'),
    ('Histórica', 'Ambientadas en el pasado'),
    ('Biografía', 'Vidas reales'),
    ('Autoayuda', 'Desarrollo personal'),
    ('Negocios', 'Empresa y emprendimiento'),
    ('Educación', 'Académicos y formación'),
    ('Poesía', 'Obras poéticas'),
    ('Drama', 'Teatro y drama'),
    ('Humor', 'Comedia y sátira'),
    ('Infantil', 'Para niños'),
    ('Juvenil', 'Para jóvenes')
ON CONFLICT (nombre) DO NOTHING;

-- Intentar migrar posibles datos antiguos si existían en backup (si tuviera columnas nombre)
DO $$
DECLARE r RECORD; cat_id INTEGER;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tbl_categorias_old_backup_20251112' AND column_name = 'nombre'
  ) THEN
    FOR r IN SELECT DISTINCT nombre FROM tbl_categorias_old_backup_20251112 WHERE nombre IS NOT NULL LOOP
      INSERT INTO public.tbl_categorias (nombre)
      VALUES (r.nombre)
      ON CONFLICT (nombre) DO NOTHING;
    END LOOP;
  END IF;
END $$;

-- Reporte final
SELECT id_categoria, nombre FROM public.tbl_categorias ORDER BY nombre;
