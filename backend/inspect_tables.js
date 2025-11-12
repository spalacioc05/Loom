// inspect_tables.js
import sql from './db/client.js';

async function main() {
  try {
    console.log('=== Columnas de tablas clave ===');
    const cols = await sql`
      SELECT table_name, column_name, data_type
      FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name IN ('tbl_libros', 'tbl_categorias', 'tbl_libros_x_categorias', 'tbl_categorias_old_backup_20251112')
      ORDER BY table_name, ordinal_position;
    `;
    console.table(cols);

    console.log('\n=== Primera fila de cada tabla (si existe) ===');
    for (const t of ['tbl_libros','tbl_categorias','tbl_libros_x_categorias','tbl_categorias_old_backup_20251112']) {
      try {
        const rows = await sql([`SELECT * FROM public.${t} LIMIT 3`]);
        console.log(`\nTabla: ${t}`);
        console.table(rows);
      } catch (e) {
        console.log(`(No se pudo leer tabla ${t}: ${e.message})`);
      }
    }
  } catch (e) {
    console.error('Error inspeccionando tablas:', e);
  } finally {
    await sql.end();
  }
}

main();
