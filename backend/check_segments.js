import dotenv from 'dotenv';
dotenv.config();

import pkg from 'pg';
const { Pool } = pkg;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const libroId = process.argv[2] || 83;

async function checkSegments() {
  try {
    // Obtener documento del libro
    const docResult = await pool.query(
      'SELECT id FROM tbl_documentos WHERE libro_id = $1 ORDER BY created_at DESC LIMIT 1',
      [libroId]
    );

    if (docResult.rows.length === 0) {
      console.log('❌ No se encontró documento para el libro', libroId);
      return;
    }

    const docId = docResult.rows[0].id;

    // Obtener primeros 10 segmentos
    const segResult = await pool.query(
      `SELECT orden, texto, LENGTH(texto) as chars
       FROM tbl_segmentos
       WHERE documento_id = $1
       ORDER BY orden ASC
       LIMIT 10`,
      [docId]
    );

    console.log(`\n📚 Primeros 10 segmentos del libro ${libroId}:\n`);
    console.log('═'.repeat(80));

    for (const seg of segResult.rows) {
      console.log(`\n[Segmento ${seg.orden}] (${seg.chars} chars)`);
      console.log('─'.repeat(80));
      console.log(seg.texto.substring(0, 300) + (seg.texto.length > 300 ? '...' : ''));
      console.log('─'.repeat(80));
    }

    // Estadísticas
    const statsResult = await pool.query(
      `SELECT 
        COUNT(*) as total,
        AVG(LENGTH(texto)) as avg_chars,
        MIN(LENGTH(texto)) as min_chars,
        MAX(LENGTH(texto)) as max_chars
       FROM tbl_segmentos
       WHERE documento_id = $1`,
      [docId]
    );

    console.log('\n📊 Estadísticas de segmentos:');
    console.log('═'.repeat(80));
    console.log(`Total segmentos: ${statsResult.rows[0].total}`);
    console.log(`Promedio chars: ${Math.round(statsResult.rows[0].avg_chars)}`);
    console.log(`Mínimo chars: ${statsResult.rows[0].min_chars}`);
    console.log(`Máximo chars: ${statsResult.rows[0].max_chars}`);
    console.log('═'.repeat(80));

  } catch (error) {
    console.error('Error:', error.message);
  } finally {
    await pool.end();
  }
}

checkSegments();
