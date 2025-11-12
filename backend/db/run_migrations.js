/**
 * Script para ejecutar migraciones de base de datos
 * Ejecutar con: node backend/db/run_migrations.js
 */

import sql from './client.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function runMigrations() {
  console.log('🚀 Iniciando migraciones...\n');

  try {
    // Verificar conexión
    await sql`SELECT 1`;
    console.log('✅ Conexión a base de datos establecida\n');

    // Migración 000: Agregar columna firebase_uid a usuarios existentes
    console.log('📝 Migración 000: Agregando columna firebase_uid...');
    try {
      await sql`
        ALTER TABLE public.tbl_usuarios 
        ADD COLUMN IF NOT EXISTS firebase_uid TEXT NULL
      `;
      console.log('   ✅ Columna firebase_uid agregada');
      
      // Crear índice si no existe
      await sql`
        CREATE INDEX IF NOT EXISTS idx_usuarios_firebase_uid 
        ON public.tbl_usuarios(firebase_uid)
      `;
      console.log('   ✅ Índice creado\n');
    } catch (err) {
      if (err.code === '42701') {
        console.log('   ℹ️  Columna firebase_uid ya existe\n');
      } else {
        throw err;
      }
    }

    // Migración 002: Crear tabla tbl_libros_x_usuarios
    console.log('📝 Migración 002: Creando tabla tbl_libros_x_usuarios...');
    try {
      await sql`
        CREATE TABLE IF NOT EXISTS public.tbl_libros_x_usuarios (
          id_usuario BIGINT NOT NULL REFERENCES public.tbl_usuarios(id_usuario) ON DELETE CASCADE,
          id_libro BIGINT NOT NULL REFERENCES public.tbl_libros(id_libro) ON DELETE CASCADE,
          fecha_ultima_lectura TIMESTAMP WITHOUT TIME ZONE NULL,
          progreso NUMERIC(5, 2) DEFAULT 0.0,
          tiempo_escucha INTEGER DEFAULT 0,
          CONSTRAINT tbl_libros_x_usuarios_pkey PRIMARY KEY (id_usuario, id_libro)
        )
      `;
      console.log('   ✅ Tabla creada');

      // Crear índices
      await sql`
        CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_usuario 
        ON public.tbl_libros_x_usuarios(id_usuario)
      `;
      await sql`
        CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_libro 
        ON public.tbl_libros_x_usuarios(id_libro)
      `;
      await sql`
        CREATE INDEX IF NOT EXISTS idx_libros_x_usuarios_fecha 
        ON public.tbl_libros_x_usuarios(fecha_ultima_lectura DESC)
      `;
      console.log('   ✅ Índices creados\n');
    } catch (err) {
      if (err.code === '42P07') {
        console.log('   ℹ️  Tabla tbl_libros_x_usuarios ya existe\n');
      } else {
        throw err;
      }
    }

    // Verificar estructura
    console.log('📊 Verificando estructura de tbl_usuarios...');
    const columns = await sql`
      SELECT column_name, data_type, is_nullable 
      FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'tbl_usuarios'
      ORDER BY ordinal_position
    `;
    console.log('   Columnas encontradas:');
    columns.forEach(col => {
      console.log(`   - ${col.column_name}: ${col.data_type} ${col.is_nullable === 'NO' ? '(NOT NULL)' : '(nullable)'}`);
    });

    console.log('\n🎉 ¡Migraciones completadas exitosamente!');
    // Migración 003: Agregar id_uploader y eliminado a tbl_libros
    console.log('\n📝 Migración 003: Agregando columnas id_uploader y eliminado a tbl_libros...');
    try {
      await sql`
        ALTER TABLE public.tbl_libros
        ADD COLUMN IF NOT EXISTS id_uploader BIGINT NULL REFERENCES public.tbl_usuarios(id_usuario) ON DELETE SET NULL,
        ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE
      `;
      console.log('   ✅ Columnas agregadas');
      await sql`
        CREATE INDEX IF NOT EXISTS idx_libros_uploader ON public.tbl_libros(id_uploader)
      `;
      console.log('   ✅ Índice creado');
    } catch (err) {
      console.error('   ❌ Error migración 003:', err.message);
    }

  } catch (error) {
    console.error('\n❌ Error ejecutando migraciones:', error);
    console.error('Detalles:', error.message);
    process.exit(1);
  } finally {
    await sql.end();
    process.exit(0);
  }
}

runMigrations();
