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

    // 3. Descargar PDF desde Supabase Storage (tolerante: usa fetch si existe; si falla, usa SDK de Supabase)
    console.log('Descargando PDF...');
    const pdfUrl = libro.archivo;
    let pdfBuffer;
    let fetched = false;
    try {
      if (typeof fetch === 'function') {
        const response = await fetch(pdfUrl);
        if (response.ok) {
          pdfBuffer = Buffer.from(await response.arrayBuffer());
          fetched = true;
        } else {
          console.warn(`Fetch no OK (${response.status}) para ${pdfUrl}, usando fallback por SDK`);
        }
      } else {
        console.warn('fetch no está disponible en este runtime, usando fallback por SDK');
      }
    } catch (e) {
      console.warn('Fallo al hacer fetch directo del PDF, usando fallback por SDK:', e.message);
    }

    if (!fetched) {
      // Intentar descargar con Supabase SDK (funciona aunque el bucket sea privado)
      try {
        // Inferir la ruta interna del archivo a partir de la URL pública
        // Ejemplo URL: .../storage/v1/object/public/archivos_libros/libros/archivo.pdf
        const url = new URL(pdfUrl);
        const marker = '/archivos_libros/';
        const idx = url.pathname.indexOf(marker);
        if (idx === -1) {
          throw new Error('No se pudo inferir la ruta del archivo desde la URL');
        }
        const filePath = url.pathname.substring(idx + marker.length);
        const { data, error } = await supabase.storage
          .from('archivos_libros')
          .download(filePath);
        if (error) throw error;
        const ab = await data.arrayBuffer();
        pdfBuffer = Buffer.from(ab);
      } catch (e) {
        throw new Error(`Error descargando PDF via SDK: ${e.message}`);
      }
    }

    console.log(`PDF descargado: ${pdfBuffer.length} bytes`);

    // 4. Extraer texto con pdf-parse (compatibilidad v1/v2)
    console.log('Extrayendo texto...');
    let fullText = '';
    let totalPages = null;
    try {
      if (PDFParse) {
        // Intentar API v2 basada en clase
        const parser = new PDFParse({ data: pdfBuffer });
        const result = await parser.getText();
        fullText = result.text || '';
        try {
          const info = await parser.getInfo();
          totalPages = info?.numPages || null;
        } catch (e) {
          console.warn('No se pudo obtener info de páginas (v2):', e.message);
        }
        await parser.destroy?.();
      } else {
        throw new Error('PDFParse class no disponible');
      }
    } catch (e) {
      console.warn('Fallo API v2 de pdf-parse, probando compatibilidad v1:', e.message);
      try {
        const legacyPdfParse = require('pdf-parse');
        const res = await legacyPdfParse(pdfBuffer);
        fullText = res.text || '';
        totalPages = res.numpages || null;
      } catch (e2) {
        throw new Error(`No se pudo extraer texto del PDF: ${e2.message}`);
      }
    }

    console.log(`Texto extraído: ${fullText.length} caracteres, ${totalPages || '?'} páginas`);

    if (!fullText || fullText.trim().length === 0) {
      throw new Error('No se pudo extraer texto del PDF');
    }

    // 5. Limpiar metadatos/portada: saltar los primeros ~3000 caracteres
    // que usualmente contienen: título, autor, índice, copyright, portada, etc.
    const SKIP_CHARS = 3000; // Ajustable según necesidad
    const cleanedText = fullText.length > SKIP_CHARS ? fullText.substring(SKIP_CHARS) : fullText;
    const skippedChars = fullText.length - cleanedText.length;
    
    console.log(`Omitiendo primeros ${skippedChars} caracteres (metadatos/portada)`);
    console.log(`Texto limpio: ${cleanedText.length} caracteres`);

    // 6. Generar hash del texto limpio
    const textHash = crypto.createHash('sha256').update(cleanedText).digest('hex');

    // 7. Segmentar texto limpio
    console.log('Segmentando texto...');
    const chunks = chunkTextBySentence(cleanedText, 1500);
    console.log(`Generados ${chunks.length} segmentos`);

    // 8. Limpiar segmentos existentes (si reprocessing)
    await pool.query('DELETE FROM tbl_segmentos WHERE documento_id = $1', [documentoId]);

    // 9. Insertar segmentos en BD
    console.log('Guardando segmentos en BD...');
    let currentOffset = SKIP_CHARS; // Empezar desde donde saltamos los metadatos

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

    // 10. Actualizar documento como listo (usar cleanedText.length)
    await pool.query(
      `UPDATE tbl_documentos 
       SET estado = 'listo', 
           texto_hash = $1, 
           total_caracteres = $2, 
           total_segmentos = $3,
           updated_at = NOW()
       WHERE id = $4`,
      [textHash, cleanedText.length, chunks.length, documentoId]
    );

    console.log(`\n✅ Procesamiento completado exitosamente`);
    console.log(`   Total caracteres: ${cleanedText.length} (${skippedChars} caracteres omitidos)`);
    console.log(`   Total segmentos: ${chunks.length}`);
    console.log(`   Estado: listo\n`);

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
