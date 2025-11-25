require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

console.log('🔄 Actualizando voces a español e inglés...');

const sql = `
DELETE FROM tbl_voces WHERE proveedor = 'google';

INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  ('google', 'es-Normal', 'es', '{"slow": false}', true),
  ('google', 'es-Clara', 'es', '{"slow": true}', true),
  ('google', 'en-Normal', 'en', '{"slow": false}', true),
  ('google', 'en-Clear', 'en', '{"slow": true}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;
`;

pool.query(sql)
  .then(() => {
    console.log('✅ Voces actualizadas');
    return pool.query('SELECT id, proveedor, codigo_voz, idioma FROM tbl_voces WHERE activo = true ORDER BY idioma, codigo_voz');
  })
  .then(r => {
    console.log(`\n🎤 Voces activas (${r.rows.length}):`);
    r.rows.forEach(v => console.log(`  ${v.idioma}: ${v.codigo_voz}`));
    pool.end();
    process.exit(0);
  })
  .catch(e => {
    console.error('❌ Error:', e.message);
    pool.end();
    process.exit(1);
  });
