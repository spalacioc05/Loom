// inspect_schema.js
import sql from './db/client.js';

async function inspect() {
  try {
    console.log('Inspecting public.tbl_categorias columns...');
    const cols = await sql`
      SELECT column_name, data_type
      FROM information_schema.columns
      WHERE table_schema='public' AND table_name='tbl_categorias'
      ORDER BY ordinal_position
    `;
    console.table(cols);

    console.log('\nFirst rows from tbl_categorias (if any):');
    const rows = await sql`SELECT * FROM public.tbl_categorias LIMIT 5`;
    console.table(rows);
  } catch (e) {
    console.error('Error inspecting schema:', e);
  } finally {
    await sql.end();
  }
}

inspect();
