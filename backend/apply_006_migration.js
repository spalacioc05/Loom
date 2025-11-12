import 'dotenv/config';
import sql from './db/client.js';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function applyMigration() {
  const migrationPath = path.join(__dirname, 'db', 'migrations', '006_update_voices_google_tts.sql');
  
  console.log('📋 Aplicando migración 006: Voces de Google TTS\n');
  
  try {
    const sqlText = await fs.readFile(migrationPath, 'utf-8');
    
    console.log('Ejecutando SQL...');
    await sql.unsafe(sqlText);
    
    console.log('✅ Migración aplicada exitosamente\n');
    
    // Mostrar voces activas
    const activas = await sql`
      SELECT proveedor, codigo_voz, idioma 
      FROM tbl_voces 
      WHERE activo = true
      ORDER BY proveedor, idioma, codigo_voz
    `;
    
    const inactivas = await sql`
      SELECT COUNT(*)::int as count
      FROM tbl_voces 
      WHERE activo = false
    `;
    
    console.log(`🎙️  Voces activas (${activas.length}):`);
    activas.forEach(v => {
      console.log(`   ${v.proveedor.padEnd(8)} ${v.codigo_voz.padEnd(20)} ${v.idioma}`);
    });
    
    console.log(`\n⏸️  Voces inactivas: ${inactivas[0].count} (Azure desactivadas)`);
    
  } catch (error) {
    console.error('❌ Error aplicando migración:', error.message);
    throw error;
  } finally {
    await sql.end();
  }
}

applyMigration()
  .then(() => process.exit(0))
  .catch(() => process.exit(1));

