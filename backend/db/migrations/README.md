# Migraciones de Base de Datos

Este directorio contiene las migraciones SQL para configurar las tablas necesarias para la autenticación con Firebase.

## Estructura Actual de Supabase

Tu base de datos ya tiene la tabla `tbl_usuarios` creada. Solo necesitas agregar la columna `firebase_uid` para integrar Firebase Authentication.

## Archivos de Migración

### `000_usuarios.sql`
- **Propósito:** Documentación de la estructura de `tbl_usuarios`
- **Acción:** Agrega columna `firebase_uid` a tabla existente
- **Estado:** La tabla ya existe, solo falta la columna

### `002_user_library.sql`
- **Propósito:** Crear tabla `tbl_libros_x_usuarios` para biblioteca personal
- **Acción:** Relaciona usuarios con libros (con progreso de lectura)
- **Dependencia:** Requiere que `tbl_usuarios` exista

### `run_all_migrations.sql`
- **Propósito:** Script SQL completo para ejecutar en Supabase
- **Uso:** Copiar y pegar en SQL Editor de Supabase
- **Incluye:** Ambas migraciones + verificaciones

### `run_migrations.js`
- **Propósito:** Script Node.js para ejecutar migraciones automáticamente
- **Uso:** `node backend/db/run_migrations.js`
- **Ventaja:** Verifica y reporta el estado de cada migración

## Cómo Ejecutar las Migraciones

### Opción 1: Script Node.js (Recomendado)

```bash
cd backend
node db/run_migrations.js
```

Este script:
- ✅ Verifica la conexión a la base de datos
- ✅ Agrega columna `firebase_uid` si no existe
- ✅ Crea tabla `tbl_libros_x_usuarios` si no existe
- ✅ Crea todos los índices necesarios
- ✅ Muestra la estructura final de la tabla
- ✅ Maneja errores de forma segura (no falla si ya existe)

### Opción 2: SQL Editor de Supabase

1. Abre tu proyecto en [Supabase Dashboard](https://app.supabase.com)
2. Ve a **SQL Editor**
3. Copia el contenido de `run_all_migrations.sql`
4. Pega y ejecuta (Run)

### Opción 3: Migraciones Individuales

Si prefieres ejecutar una por una:

```bash
# Solo agregar firebase_uid
psql $DATABASE_URL -f backend/db/migrations/000_usuarios.sql

# Crear tabla de biblioteca
psql $DATABASE_URL -f backend/db/migrations/002_user_library.sql
```

## Verificar Estado de las Migraciones

### Verificar columna firebase_uid

```sql
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'tbl_usuarios'
  AND column_name = 'firebase_uid';
```

**Resultado esperado:**
```
column_name  | data_type | is_nullable
firebase_uid | text      | YES
```

### Verificar tabla tbl_libros_x_usuarios

```sql
SELECT EXISTS (
  SELECT 1 
  FROM information_schema.tables 
  WHERE table_schema = 'public' 
    AND table_name = 'tbl_libros_x_usuarios'
);
```

**Resultado esperado:** `true`

## Rollback (Revertir Migraciones)

Si necesitas revertir los cambios:

### Eliminar columna firebase_uid

```sql
ALTER TABLE public.tbl_usuarios 
DROP COLUMN IF EXISTS firebase_uid;

DROP INDEX IF EXISTS idx_usuarios_firebase_uid;
```

### Eliminar tabla de biblioteca

```sql
DROP TABLE IF EXISTS public.tbl_libros_x_usuarios CASCADE;
```

⚠️ **ADVERTENCIA:** Eliminar `tbl_libros_x_usuarios` borrará toda la información de biblioteca personal de los usuarios.

## Estructura Final

Después de las migraciones, tu base de datos tendrá:

### tbl_usuarios
```
id_usuario       BIGINT (PK)
id_supabase      TEXT (UNIQUE)
nombre           TEXT (UNIQUE, NOT NULL)
correo           TEXT (UNIQUE, NOT NULL)
fecha_registro   TIMESTAMP
foto_perfil      TEXT
id_estado        BIGINT
ultimo_login     TIMESTAMP
firebase_uid     TEXT  ← NUEVO
```

### tbl_libros_x_usuarios
```
id_usuario            BIGINT (PK, FK → tbl_usuarios)
id_libro              BIGINT (PK, FK → tbl_libros)
fecha_ultima_lectura  TIMESTAMP
progreso              NUMERIC(5,2)  -- 0.00 a 100.00%
tiempo_escucha        INTEGER       -- segundos
```

## Próximos Pasos

Después de ejecutar las migraciones:

1. ✅ Reiniciar el backend: `node index.js`
2. ✅ Probar login desde el frontend
3. ✅ Verificar que se cree el usuario en la base de datos
4. ✅ Verificar logs del backend para confirmar creación/actualización

## Troubleshooting

### Error: "relation tbl_libros does not exist"

La tabla `tbl_libros_x_usuarios` requiere que exista `tbl_libros`. Verifica:

```sql
SELECT tablename 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename LIKE '%libro%';
```

### Error: "duplicate key value violates unique constraint"

Si intentas crear un usuario con un `nombre` que ya existe, el backend retornará error 409. Este es el comportamiento esperado debido al constraint `UNIQUE(nombre)`.

**Solución:** Usa un nombre diferente o modifica la tabla para permitir nombres duplicados (no recomendado).

### No se conecta a la base de datos

Verifica tu configuración en `backend/config/supabase.js` o variables de entorno.

```bash
# Ver configuración actual
node -e "import('./config/supabase.js').then(c => console.log(c.default))"
```
