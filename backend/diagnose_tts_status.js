import 'dotenv/config';
import sql from './db/client.js';

/**
 * Uso: node diagnose_tts_status.js 1 2 3
 * Muestra estado del documento, segmentos y audios por libro.
 */
async function run() {
  const libroIds = process.argv.slice(2).map(n => parseInt(n, 10)).filter(n => !isNaN(n));
  if (!libroIds.length) {
    console.log('Indica IDs de libros. Ej: node diagnose_tts_status.js 1 2 3');
    process.exit(0);
  }

  for (const id of libroIds) {
    console.log('\n=== Libro', id, '===');
    const doc = await sql`SELECT id, estado, total_segmentos FROM tbl_documentos WHERE libro_id = ${id} ORDER BY updated_at DESC LIMIT 1`;
    if (!doc.length) {
      console.log('Documento: (no existe)');
      continue;
    }
    const documentoId = doc[0].id;
    console.log('Documento:', documentoId, 'estado=', doc[0].estado, 'total_segmentos=', doc[0].total_segmentos);

    const segCount = await sql`SELECT count(*)::int AS c FROM tbl_segmentos WHERE documento_id = ${documentoId}`;
    console.log('Segmentos en tabla:', segCount[0].c);

    const firstSegs = await sql`SELECT id, orden FROM tbl_segmentos WHERE documento_id = ${documentoId} ORDER BY orden LIMIT 5`;
    console.log('Primeros segmentos:', firstSegs.map(s => `${s.orden}:${s.id}`).join(', ') || '(ninguno)');

    const voices = await sql`SELECT id, codigo_voz FROM tbl_voces WHERE activo = true LIMIT 3`;
    console.log('Voces activas:', voices.map(v => v.codigo_voz).join(', ') || '(ninguna)');

    if (!voices.length) {
      console.log('⚠️ Sin voces activas no se generarán audios.');
    } else if (firstSegs.length) {
      // contar audios generados
      const audioCount = await sql`SELECT count(*)::int AS c FROM tbl_audios WHERE documento_id = ${documentoId}`;
      console.log('Audios totales:', audioCount[0].c);
      const missing = await sql`SELECT s.id, s.orden FROM tbl_segmentos s LEFT JOIN tbl_audios a ON a.segmento_id = s.id AND a.voz_id = ${voices[0].id} WHERE s.documento_id = ${documentoId} AND a.id IS NULL ORDER BY s.orden LIMIT 5`;
      console.log('Primeros faltantes voz', voices[0].codigo_voz, ':', missing.map(m => m.orden).join(', ') || '(ninguno)');
    }
  }

  await sql.end();
}

run().catch(e => { console.error(e); process.exit(1); });
