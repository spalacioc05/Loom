import sql from './db/client.js';

async function cleanSegments() {
  try {
    console.log('Eliminando segmentos del libro 83...');
    
    // Primero ver cuántos hay
    const count = await sql`
      SELECT COUNT(*) as total
      FROM tbl_segmentos s
      JOIN tbl_documentos d ON s.documento_id = d.id
      WHERE d.libro_id = 83
    `;
    
    console.log(`Segmentos actuales: ${count[0].total}`);
    
    // Eliminar
    const result = await sql`
      DELETE FROM tbl_segmentos 
      WHERE documento_id IN (
        SELECT id FROM tbl_documentos WHERE libro_id = 83
      )
    `;
    
    console.log(`✅ Eliminados ${result.count} segmentos para libro 83`);
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

cleanSegments();
