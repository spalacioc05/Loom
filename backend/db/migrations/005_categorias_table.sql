-- 005_categorias_table.sql
-- Crear tabla de categorías y relación many-to-many con libros

-- 1. Crear tabla de categorías
CREATE TABLE IF NOT EXISTS public.tbl_categorias (
    id_categoria SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE public.tbl_categorias IS 'Catálogo de categorías disponibles para clasificar libros';
COMMENT ON COLUMN public.tbl_categorias.nombre IS 'Nombre único de la categoría';

-- 2. Crear tabla de relación many-to-many entre libros y categorías
CREATE TABLE IF NOT EXISTS public.tbl_libros_x_categorias (
    id_libro INTEGER NOT NULL,
    id_categoria INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_libro, id_categoria),
    FOREIGN KEY (id_libro) REFERENCES public.tbl_libros(id_libro) ON DELETE CASCADE,
    FOREIGN KEY (id_categoria) REFERENCES public.tbl_categorias(id_categoria) ON DELETE CASCADE
);

COMMENT ON TABLE public.tbl_libros_x_categorias IS 'Relación many-to-many: un libro puede tener múltiples categorías';

-- 3. Índices para optimizar búsquedas
CREATE INDEX IF NOT EXISTS idx_libros_x_categorias_libro ON public.tbl_libros_x_categorias(id_libro);
CREATE INDEX IF NOT EXISTS idx_libros_x_categorias_categoria ON public.tbl_libros_x_categorias(id_categoria);

-- 4. Insertar categorías predefinidas
INSERT INTO public.tbl_categorias (nombre, descripcion) VALUES
    ('General', 'Categoría general para libros sin clasificación específica'),
    ('Aventura', 'Historias de acción y aventuras emocionantes'),
    ('Romance', 'Historias románticas y de amor'),
    ('Ciencia Ficción', 'Ficción especulativa basada en avances científicos y tecnológicos'),
    ('Fantasía', 'Mundos imaginarios con magia y criaturas fantásticas'),
    ('Misterio', 'Novelas de suspenso, crimen e investigación'),
    ('Terror', 'Historias de horror y suspenso psicológico'),
    ('Histórica', 'Narrativas ambientadas en períodos históricos'),
    ('Biografía', 'Relatos de vidas reales y memorias'),
    ('Autoayuda', 'Desarrollo personal y crecimiento'),
    ('Negocios', 'Gestión empresarial y emprendimiento'),
    ('Educación', 'Textos educativos y académicos'),
    ('Poesía', 'Obras poéticas y líricas'),
    ('Drama', 'Obras dramáticas y teatro'),
    ('Humor', 'Comedias y sátiras'),
    ('Infantil', 'Libros para niños y primeros lectores'),
    ('Juvenil', 'Literatura para adolescentes y jóvenes')
ON CONFLICT (nombre) DO NOTHING;

-- 5. Migrar datos existentes de la columna 'categoria' a la tabla de relación
-- (este bloque se ejecutará solo si existen libros con categorías en la columna antigua)
DO $$
DECLARE
    libro_record RECORD;
    cat_id INTEGER;
BEGIN
    -- Solo ejecutar si la columna categoria existe
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'tbl_libros' 
        AND column_name = 'categoria'
    ) THEN
        -- Iterar sobre libros que tienen categoría
        FOR libro_record IN 
            SELECT id_libro, categoria 
            FROM public.tbl_libros 
            WHERE categoria IS NOT NULL AND categoria != ''
        LOOP
            -- Buscar o crear la categoría
            SELECT id_categoria INTO cat_id 
            FROM public.tbl_categorias 
            WHERE nombre = libro_record.categoria;
            
            -- Si no existe, crearla
            IF cat_id IS NULL THEN
                INSERT INTO public.tbl_categorias (nombre) 
                VALUES (libro_record.categoria)
                RETURNING id_categoria INTO cat_id;
            END IF;
            
            -- Crear la relación (ignorar si ya existe)
            INSERT INTO public.tbl_libros_x_categorias (id_libro, id_categoria)
            VALUES (libro_record.id_libro, cat_id)
            ON CONFLICT DO NOTHING;
        END LOOP;
        
        RAISE NOTICE 'Migración de categorías completada';
    END IF;
END $$;

-- 6. OPCIONAL: Eliminar la columna 'categoria' antigua después de verificar la migración
-- NOTA: Comentado por seguridad. Descomentar solo después de verificar que todo funciona correctamente
-- ALTER TABLE public.tbl_libros DROP COLUMN IF EXISTS categoria;

-- Verificación: contar categorías migradas
SELECT 
    c.nombre as categoria,
    COUNT(lxc.id_libro) as total_libros
FROM public.tbl_categorias c
LEFT JOIN public.tbl_libros_x_categorias lxc ON c.id_categoria = lxc.id_categoria
GROUP BY c.nombre
ORDER BY total_libros DESC, c.nombre;
