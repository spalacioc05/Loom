import sql from './db/client.js';
import fs from 'fs';

async function runTTSMigration() {
  try {
    console.log('🚀 Ejecutando migración de TTS...\n');
    
    const migrationSQL = fs.readFileSync('./db/migrations/001_tts_tables.sql', 'utf8');
    
    // Ejecutar la migración completa
    await sql.unsafe(migrationSQL);
    
    console.log('✅ Migración de TTS completada exitosamente\n');
    
    // Verificar que las tablas se crearon
    const tables = await sql`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name IN ('tbl_documentos', 'tbl_segmentos', 'tbl_voces', 'tbl_audios', 'tbl_progreso')
      ORDER BY table_name
    `;
    
    console.log('Tablas creadas:');
    tables.forEach(t => console.log(`  - ${t.table_name}`));
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

runTTSMigration();
