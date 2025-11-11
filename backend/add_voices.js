import dotenv from 'dotenv';
dotenv.config();

import pkg from 'pg';
const { Pool } = pkg;
import fs from 'fs';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

async function addVoices() {
  try {
    console.log('🎤 Agregando nuevas voces...\n');

    const sql = fs.readFileSync('./db/migrations/003_add_more_voices.sql', 'utf8');
    
    await pool.query(sql);
    
    console.log('✅ Voces agregadas exitosamente!\n');
    
    // Mostrar todas las voces
    const result = await pool.query(`
      SELECT codigo_voz, idioma 
      FROM tbl_voces 
      WHERE activo = true 
      ORDER BY idioma, codigo_voz
    `);
    
    console.log(`📊 Total de voces disponibles: ${result.rows.length}\n`);
    
    // Agrupar por idioma
    const porIdioma = result.rows.reduce((acc, row) => {
      if (!acc[row.idioma]) acc[row.idioma] = [];
      acc[row.idioma].push(row.codigo_voz);
      return acc;
    }, {});
    
    for (const [idioma, voces] of Object.entries(porIdioma)) {
      console.log(`${idioma} (${voces.length}):`);
      voces.forEach(voz => console.log(`  - ${voz}`));
      console.log('');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await pool.end();
  }
}

addVoices();
