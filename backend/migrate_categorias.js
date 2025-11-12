// migrate_categorias.js
// Script para ejecutar la migración de categorías y verificar resultados

import sql from './db/client.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function runMigration() {
  console.log('🚀 Iniciando migración de categorías...\n');

  try {
    // Leer el archivo de migración
    const migrationPath = path.join(__dirname, 'db', 'migrations', '005_categorias_table.sql');
    const migrationSQL = fs.readFileSync(migrationPath, 'utf8');

    console.log('📄 Ejecutando migración 005_categorias_table.sql...');
    
    // Ejecutar la migración
    await sql.unsafe(migrationSQL);
    
    console.log('✅ Migración ejecutada exitosamente!\n');

    // Verificar categorías creadas
    console.log('📊 Categorías disponibles:');
    const categorias = await sql`
      SELECT id_categoria, nombre, descripcion 
      FROM tbl_categorias 
      ORDER BY nombre
    `;
    
    console.table(categorias.map(c => ({
      ID: c.id_categoria,
      Nombre: c.nombre,
      Descripción: c.descripcion ? c.descripcion.substring(0, 50) + '...' : 'N/A'
    })));

    // Verificar libros migrados
    console.log('\n📚 Resumen de libros por categoría:');
    const resumen = await sql`
      SELECT 
        c.nombre as categoria,
        COUNT(lxc.id_libro) as total_libros
      FROM tbl_categorias c
      LEFT JOIN tbl_libros_x_categorias lxc ON c.id_categoria = lxc.id_categoria
      GROUP BY c.nombre
      ORDER BY total_libros DESC, c.nombre
    `;
    
    console.table(resumen.map(r => ({
      Categoría: r.categoria,
      'Total Libros': r.total_libros
    })));

    // Verificar libros con múltiples categorías
    const librosMultiples = await sql`
      SELECT 
        l.id_libro,
        l.titulo,
        COUNT(lxc.id_categoria) as num_categorias,
        STRING_AGG(c.nombre, ', ' ORDER BY c.nombre) as categorias
      FROM tbl_libros l
      LEFT JOIN tbl_libros_x_categorias lxc ON l.id_libro = lxc.id_libro
      LEFT JOIN tbl_categorias c ON lxc.id_categoria = c.id_categoria
      GROUP BY l.id_libro, l.titulo
      HAVING COUNT(lxc.id_categoria) > 0
      ORDER BY num_categorias DESC
      LIMIT 10
    `;

    if (librosMultiples.length > 0) {
      console.log('\n📖 Primeros 10 libros con categorías asignadas:');
      console.table(librosMultiples.map(l => ({
        ID: l.id_libro,
        Título: l.titulo.substring(0, 40),
        '# Categorías': l.num_categorias,
        Categorías: l.categorias
      })));
    }

    // Verificar si aún existe la columna antigua 'categoria'
    const columnExists = await sql`
      SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'tbl_libros' 
        AND column_name = 'categoria'
      ) as exists
    `;

    if (columnExists[0].exists) {
      console.log('\n⚠️  NOTA: La columna antigua "categoria" aún existe en tbl_libros');
      console.log('   Una vez verificado que todo funciona, puedes eliminarla con:');
      console.log('   ALTER TABLE public.tbl_libros DROP COLUMN categoria;');
    } else {
      console.log('\n✅ La columna antigua "categoria" ha sido eliminada correctamente');
    }

    console.log('\n✨ Migración completada exitosamente!\n');

  } catch (error) {
    console.error('❌ Error durante la migración:', error);
    console.error('Detalles:', error.message);
    process.exit(1);
  } finally {
    await sql.end();
  }
}

// Ejecutar
runMigration();
