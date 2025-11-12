-- fix_categories_full.sql
-- 1) Rehacer catálogo de categorías correctamente
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='tbl_categorias'
  ) THEN
    -- Si existe pero no tiene columna nombre, renombrar y crear nueva
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='tbl_categorias' AND column_name='nombre'
    ) THEN
      EXECUTE 'ALTER TABLE public.tbl_categorias RENAME TO tbl_categorias_old_backup_20251112';
      EXECUTE 'CREATE TABLE public.tbl_categorias (
        id_categoria SERIAL PRIMARY KEY,
        nombre VARCHAR(100) NOT NULL UNIQUE,
        descripcion TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )';
    END IF;
  ELSE
    -- No existe: crearla
    EXECUTE 'CREATE TABLE public.tbl_categorias (
      id_categoria SERIAL PRIMARY KEY,
      nombre VARCHAR(100) NOT NULL UNIQUE,
      descripcion TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )';
  END IF;
END $$;

-- 2) Rehacer tabla de relación correctamente (drop y create limpio)
DROP TABLE IF EXISTS public.tbl_libros_x_categorias CASCADE;
CREATE TABLE public.tbl_libros_x_categorias (
  id_libro INTEGER NOT NULL,
  id_categoria INTEGER NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_libro, id_categoria),
  FOREIGN KEY (id_libro) REFERENCES public.tbl_libros(id_libro) ON DELETE CASCADE,
  FOREIGN KEY (id_categoria) REFERENCES public.tbl_categorias(id_categoria) ON DELETE CASCADE
);
CREATE INDEX idx_libros_x_categorias_libro ON public.tbl_libros_x_categorias(id_libro);
CREATE INDEX idx_libros_x_categorias_categoria ON public.tbl_libros_x_categorias(id_categoria);

-- 3) Semillas de categorías comunes
INSERT INTO public.tbl_categorias (nombre, descripcion) VALUES
  ('General','Categoría general'),
  ('Aventura','Acción y aventuras'),
  ('Romance','Historias románticas'),
  ('Ciencia Ficción','Ficción especulativa'),
  ('Fantasía','Magia y mundos imaginarios'),
  ('Misterio','Suspenso e investigación'),
  ('Terror','Horror y suspenso'),
  ('Histórica','Ambientadas en el pasado'),
  ('Biografía','Vidas reales'),
  ('Autoayuda','Desarrollo personal'),
  ('Negocios','Empresa y emprendimiento'),
  ('Educación','Académicos y formación'),
  ('Poesía','Obras poéticas'),
  ('Drama','Teatro y drama'),
  ('Humor','Comedia y sátira'),
  ('Infantil','Para niños'),
  ('Juvenil','Para jóvenes')
ON CONFLICT (nombre) DO NOTHING;

-- 4) Migración desde columna antigua tbl_libros.categoria (si existe)
DO $$
DECLARE r RECORD; cat_id INTEGER; cat_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='tbl_libros' AND column_name='categoria'
  ) THEN
    FOR r IN SELECT id_libro, categoria FROM public.tbl_libros WHERE categoria IS NOT NULL AND categoria <> '' LOOP
      cat_name := r.categoria;
      -- Asegurar categoría en catálogo
      SELECT id_categoria INTO cat_id FROM public.tbl_categorias WHERE nombre = cat_name;
      IF cat_id IS NULL THEN
        INSERT INTO public.tbl_categorias (nombre) VALUES (cat_name) RETURNING id_categoria INTO cat_id;
      END IF;
      -- Relacionar libro-categoría (ignorar duplicados)
      INSERT INTO public.tbl_libros_x_categorias (id_libro, id_categoria)
      VALUES (r.id_libro, cat_id)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;
END $$;

-- 5) Reporte
SELECT c.id_categoria, c.nombre, COUNT(lc.id_libro) AS total_libros
FROM public.tbl_categorias c
LEFT JOIN public.tbl_libros_x_categorias lc ON c.id_categoria = lc.id_categoria
GROUP BY c.id_categoria, c.nombre
ORDER BY c.nombre;
