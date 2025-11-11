/**
 * Worker de segmentación de PDFs
 * 
 * Extrae texto completo de un PDF, lo divide en chunks de ~1500 caracteres
 * respetando límites de oraciones, y guarda los segmentos en la base de datos.
 * 
 * Uso: node process_pdf.js <libro_id>
 */

import dotenv from 'dotenv';
dotenv.config();

import pkg from 'pg';
const { Pool } = pkg;
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
// En pdf-parse v2.x, usar PDFParse class
const { PDFParse } = require('pdf-parse');
import { createClient } from '@supabase/supabase-js';
import { enqueueBatch } from '../services/tts_queue.js';
import crypto from 'crypto';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

/**
 * Divide texto en chunks por oraciones, respetando límite de caracteres.
 */
function chunkTextBySentence(text, maxLen = 1500) {
  // Dividir en oraciones manteniendo puntuación
  const sentences = text.split(/([\.!?…]+)\s+/);
  const chunks = [];
  let buf = '';

  for (let i = 0; i < sentences.length; i += 2) {
    const sentence = (sentences[i] || '') + (sentences[i + 1] || '');
    
    if ((buf + ' ' + sentence).length > maxLen && buf.length > 0) {
      chunks.push(buf.trim());
      buf = sentence;
    } else {
      buf += (buf ? ' ' : '') + sentence;
    }
  }

  if (buf.trim()) {
    chunks.push(buf.trim());
  }

  return chunks;
}

/**
 * Procesa un libro: descarga PDF, extrae texto, segmenta y guarda en BD.
 */
async function processPdf(libroId) {
  console.log(`\n=== Procesando libro ID: ${libroId} ===\n`);

  try {
    // 1. Obtener información del libro
    const libroResult = await pool.query(
      'SELECT id_libro as id, titulo, archivo FROM tbl_libros WHERE id_libro = $1',
      [libroId]
    );

    if (libroResult.rows.length === 0) {
      throw new Error(`Libro con ID ${libroId} no encontrado`);
    }

    const libro = libroResult.rows[0];
    console.log(`Libro: ${libro.titulo}`);
    console.log(`PDF URL: ${libro.archivo}`);

    if (!libro.archivo) {
      throw new Error('El libro no tiene archivo PDF');
    }

    // 2. Crear o actualizar documento
    const docResult = await pool.query(
      `INSERT INTO tbl_documentos (libro_id, estado)
       VALUES ($1, 'procesando')
       ON CONFLICT (libro_id) 
       DO UPDATE SET estado = 'procesando', updated_at = NOW()
       RETURNING id`,
      [libroId]
    );
    const documentoId = docResult.rows[0].id;
    console.log(`Documento ID: ${documentoId}`);

    // 3. Descargar PDF desde Supabase Storage
    console.log('Descargando PDF...');
    const pdfUrl = libro.archivo;
    const response = await fetch(pdfUrl);
    if (!response.ok) {
      throw new Error(`Error descargando PDF: ${response.statusText}`);
    }
    const pdfBuffer = Buffer.from(await response.arrayBuffer());
    console.log(`PDF descargado: ${pdfBuffer.length} bytes`);

    // 4. Extraer texto con pdf-parse v2
    console.log('Extrayendo texto...');
    const parser = new PDFParse({ data: pdfBuffer });
    const result = await parser.getText();
    const fullText = result.text;
    // Obtener info de páginas con getInfo (puede fallar, usar null si falla)
    let totalPages = null;
    try {
      const info = await parser.getInfo();
      totalPages = info.numPages || null;
    } catch (e) {
      console.warn('No se pudo obtener info de páginas:', e.message);
    }
    await parser.destroy();
    
    console.log(`Texto extraído: ${fullText.length} caracteres, ${totalPages || '?'} páginas`);

    if (!fullText || fullText.trim().length === 0) {
      throw new Error('No se pudo extraer texto del PDF');
    }

    // 5. Generar hash del texto
    const textHash = crypto.createHash('sha256').update(fullText).digest('hex');

    // 6. Segmentar texto
    console.log('Segmentando texto...');
    const chunks = chunkTextBySentence(fullText, 1500);
    console.log(`Generados ${chunks.length} segmentos`);

    // 7. Limpiar segmentos existentes (si reprocessing)
    await pool.query('DELETE FROM tbl_segmentos WHERE documento_id = $1', [documentoId]);

    // 8. Insertar segmentos en BD
    console.log('Guardando segmentos en BD...');
    let currentOffset = 0;

    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      const startChar = currentOffset;
      const endChar = currentOffset + chunk.length;
      const segmentHash = crypto.createHash('sha256').update(chunk).digest('hex');

      // Estimar páginas (aproximación simple, solo si tenemos totalPages)
      let pageStart = null;
      let pageEnd = null;
      if (totalPages && totalPages > 0) {
        const avgCharsPerPage = fullText.length / totalPages;
        pageStart = Math.floor(startChar / avgCharsPerPage) + 1;
        pageEnd = Math.ceil(endChar / avgCharsPerPage);
      }

      await pool.query(
        `INSERT INTO tbl_segmentos 
         (documento_id, orden, pagina_inicio, pagina_fin, char_inicio, char_fin, texto, texto_hash)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [documentoId, i, pageStart, pageEnd, startChar, endChar, chunk, segmentHash]
      );

      currentOffset = endChar;
    }

    // 9. Actualizar documento como listo
    await pool.query(
      `UPDATE tbl_documentos 
       SET estado = 'listo', 
           texto_hash = $1, 
           total_caracteres = $2, 
           total_segmentos = $3,
           updated_at = NOW()
       WHERE id = $4`,
      [textHash, fullText.length, chunks.length, documentoId]
    );

    console.log(`\n✅ Procesamiento completado exitosamente`);
    console.log(`   Total caracteres: ${fullText.length}`);
    console.log(`   Total segmentos: ${chunks.length}`);
    console.log(`   Estado: listo\n`);

    // 10. Encolar generación inicial para todas las voces activas (si Redis está disponible)
    try {
      const voicesRes = await pool.query(`SELECT id FROM tbl_voces WHERE activo = true`);
      const voiceIds = voicesRes.rows.map(r => r.id);
      const segsRes = await pool.query(
        `SELECT id FROM tbl_segmentos WHERE documento_id = $1 ORDER BY orden LIMIT 30`,
        [documentoId]
      );
      const segmentIds = segsRes.rows.map(r => r.id);
      if (voiceIds.length && segmentIds.length) {
        console.log(`[Segmentación] Encolando ${segmentIds.length} segmentos para ${voiceIds.length} voces...`);
        for (const vId of voiceIds) {
          await enqueueBatch(documentoId, segmentIds, vId, { basePriority: 10 });
        }
      } else {
        console.log('[Segmentación] No hay voces o segmentos para encolar.');
      }
    } catch (e) {
      console.warn('[Segmentación] No se pudo encolar generación inicial:', e.message);
    }

    return documentoId;
  } catch (error) {
    console.error('❌ Error procesando PDF:', error);
    
    // Marcar documento como error
    try {
      await pool.query(
        `UPDATE tbl_documentos 
         SET estado = 'error', updated_at = NOW()
         WHERE libro_id = $1`,
        [libroId]
      );
    } catch (updateError) {
      console.error('Error actualizando estado a error:', updateError);
    }

    throw error;
  }
}

// Ejecutar si se llama directamente
if (process.argv[2]) {
  const libroId = parseInt(process.argv[2], 10);
  
  if (isNaN(libroId)) {
    console.error('❌ Uso: node process_pdf.js <libro_id>');
    process.exit(1);
  }

  processPdf(libroId)
    .then(() => {
      console.log('Proceso finalizado');
      process.exit(0);
    })
    .catch((error) => {
      console.error('Proceso falló:', error);
      process.exit(1);
    });
}

export { processPdf, chunkTextBySentence };
