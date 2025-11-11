import sql from './db/client.js';

async function checkTable() {
  try {
    const cols = await sql`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name='tbl_usuarios' 
      ORDER BY ordinal_position
    `;
    
    console.log('📋 Columnas en tbl_usuarios:');
    cols.forEach(c => console.log(`  - ${c.column_name} (${c.data_type})`));
    
    const count = await sql`SELECT COUNT(*)::int as total FROM tbl_usuarios`;
    console.log(`\n👥 Total usuarios: ${count[0].total}`);
    
    process.exit(0);
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

checkTable();
