require('dotenv').config();
const { Pool } = require('pg');
const fs = require('fs');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

console.log('📝 Aplicando migración 008...');
const sql = fs.readFileSync('./db/migrations/008_simplify_free_voices.sql', 'utf8');

pool.query(sql)
  .then(() => {
    console.log('✅ Migración 008 aplicada exitosamente');
    return pool.query('SELECT id, proveedor, codigo_voz, idioma FROM tbl_voces WHERE activo = true ORDER BY proveedor, codigo_voz');
  })
  .then(r => {
    console.log(`\n🎤 Voces activas (${r.rows.length}):`);
    r.rows.forEach(v => console.log(`  - [${v.proveedor}] ${v.codigo_voz} (${v.idioma})`));
    pool.end();
    process.exit(0);
  })
  .catch(e => {
    console.error('❌ Error:', e.message);
    pool.end();
    process.exit(1);
  });
