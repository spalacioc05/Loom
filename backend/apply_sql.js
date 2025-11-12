// apply_sql.js
import sql from './db/client.js';
import fs from 'fs';

const path = process.argv[2];
if (!path) {
  console.error('Usage: node apply_sql.js <path-to-sql-file>');
  process.exit(1);
}

(async () => {
  try {
    const sqltxt = fs.readFileSync(path, 'utf8');
    await sql.unsafe(sqltxt);
    console.log('✅ Applied SQL file:', path);
  } catch (e) {
    console.error('❌ Error applying SQL:', e);
    process.exit(1);
  } finally {
    await sql.end();
  }
})();
