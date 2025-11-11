/**
 * Script independiente para procesar un PDF completamente
 * Sin dependencias de nodemon ni duplicaciones
 */

import dotenv from 'dotenv';
dotenv.config();

import pkg from 'pg';
const { Pool } = pkg;
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const { PDFParse } = require('pdf-parse');
import { createClient } from '@supabase/supabase-js';
import crypto from 'crypto';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

/**
 * Limpia el texto extraído del PDF removiendo metadatos, números de página,
 * headers, footers y texto basura.
 */
function cleanPdfText(rawText) {
  let text = rawText;

  // 1. Remover líneas que son solo números (números de página)
  text = text.replace(/^\s*\d+\s*$/gm, '');

  // 2. Remover patrones comunes de headers/footers
  // Ejemplo: "-- 1 of 65 --", "Page 1", etc.
  text = text.replace(/^--\s*\d+\s*of\s*\d+\s*--$/gm, '');
  text = text.replace(/^Page\s+\d+$/gmi, '');
  text = text.replace(/^Página\s+\d+$/gmi, '');

  // 3. Remover URLs largas
  text = text.replace(/https?:\/\/[^\s]{50,}/g, '');

  // 4. Remover líneas que son solo caracteres especiales o espacios
  text = text.replace(/^[\s\-_=*#]+$/gm, '');

  // 5. Remover múltiples saltos de línea consecutivos (más de 2)
  text = text.replace(/\n{3,}/g, '\n\n');

  // 6. Remover espacios al inicio/final de cada línea
  text = text.split('\n').map(line => line.trim()).join('\n');

  // 7. Remover líneas vacías al inicio y final
  text = text.trim();

  // 8. Normalizar espacios múltiples
  text = text.replace(/ {2,}/g, ' ');

  return text;
}

/**
 * Divide texto en chunks respetando oraciones
 */
function chunkTextBySentence(text, maxLen = 1500) {
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
 * Procesar PDF: descargar, extraer texto, segmentar y guardar
 */
async function processPdf(libroId) {
  console.log(`\n=== 📚 PROCESANDO LIBRO ${libroId} ===\n`);

  try {
    // 1. Obtener información del libro
    const libroResult = await pool.query(
      'SELECT id_libro, titulo, archivo FROM tbl_libros WHERE id_libro = $1',
      [libroId]
    );

    if (libroResult.rows.length === 0) {
      throw new Error(`Libro ${libroId} no encontrado`);
    }

    const libro = libroResult.rows[0];
    console.log(`📖 Libro: ${libro.titulo}`);
    console.log(`🔗 PDF URL: ${libro.archivo}\n`);

    if (!libro.archivo) {
      throw new Error('El libro no tiene archivo PDF asociado');
    }

    // 2. Crear o obtener documento
    let documentoId;
    const docResult = await pool.query(
      'SELECT id FROM tbl_documentos WHERE libro_id = $1',
      [libroId]
    );

    if (docResult.rows.length > 0) {
      documentoId = docResult.rows[0].id;
      console.log(`📄 Documento existente: ${documentoId}`);
      
      // Actualizar estado a procesando
      await pool.query(
        'UPDATE tbl_documentos SET estado = $1, updated_at = NOW() WHERE id = $2',
        ['procesando', documentoId]
      );
    } else {
      const newDoc = await pool.query(
        'INSERT INTO tbl_documentos (libro_id, estado) VALUES ($1, $2) RETURNING id',
        [libroId, 'procesando']
      );
      documentoId = newDoc.rows[0].id;
      console.log(`📄 Documento creado: ${documentoId}`);
    }

    // 3. Descargar PDF desde Supabase
    console.log('⬇️  Descargando PDF...');
    const response = await fetch(libro.archivo);
    if (!response.ok) {
      throw new Error(`Error descargando PDF: ${response.statusText}`);
    }
    const pdfBuffer = Buffer.from(await response.arrayBuffer());
    console.log(`✅ PDF descargado: ${(pdfBuffer.length / 1024).toFixed(2)} KB\n`);

    // 4. Extraer texto
    console.log('📝 Extrayendo texto del PDF...');
    const parser = new PDFParse({ data: pdfBuffer });
    const result = await parser.getText();
    const rawText = result.text;
    
    let totalPages = null;
    try {
      const info = await parser.getInfo();
      totalPages = info.numPages || null;
    } catch (e) {
      console.warn('⚠️  No se pudo obtener número de páginas');
    }
    
    await parser.destroy();

    if (!rawText || rawText.trim().length === 0) {
      throw new Error('No se pudo extraer texto del PDF');
    }

    console.log(`✅ Texto RAW extraído: ${rawText.length.toLocaleString()} caracteres`);
    
    // 4.5. Limpiar texto (remover metadatos, números de página, etc.)
    console.log('🧹 Limpiando metadatos del PDF...');
    const cleanedText = cleanPdfText(rawText);
    const fullText = cleanedText;
    
    console.log(`✅ Texto limpio: ${fullText.length.toLocaleString()} caracteres (removidos ${(rawText.length - fullText.length).toLocaleString()})`);
    if (totalPages) console.log(`   Páginas: ${totalPages}`);
    
    // Contar palabras
    const palabras = fullText.trim().split(/\s+/).filter(p => p.length > 0);
    console.log(`   Palabras: ${palabras.length.toLocaleString()}\n`);

    // 5. Generar hash del texto
    const textHash = crypto.createHash('sha256').update(fullText).digest('hex');

    // 6. Segmentar texto
    console.log('✂️  Segmentando texto en chunks...');
    const chunks = chunkTextBySentence(fullText, 1500);
    console.log(`✅ Generados ${chunks.length} segmentos\n`);

    // 7. Limpiar segmentos anteriores
    console.log('🧹 Limpiando segmentos anteriores...');
    const deleteResult = await pool.query(
      'DELETE FROM tbl_segmentos WHERE documento_id = $1',
      [documentoId]
    );
    console.log(`   Eliminados: ${deleteResult.rowCount} segmentos antiguos\n`);

    // 8. Insertar segmentos nuevos
    console.log('💾 Guardando segmentos en la base de datos...');
    let currentOffset = 0;

    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      const startChar = currentOffset;
      const endChar = currentOffset + chunk.length;
      const segmentHash = crypto.createHash('sha256').update(chunk).digest('hex');

      // Estimar páginas
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

      currentOffset = endChar + 1;

      // Progreso cada 10 segmentos
      if ((i + 1) % 10 === 0 || i === chunks.length - 1) {
        process.stdout.write(`   Progreso: ${i + 1}/${chunks.length} segmentos\r`);
      }
    }

    console.log(`\n✅ ${chunks.length} segmentos guardados exitosamente\n`);

    // 9. Actualizar documento con estado final
    await pool.query(
      `UPDATE tbl_documentos 
       SET estado = $1, 
           texto_hash = $2, 
           total_caracteres = $3, 
           total_segmentos = $4,
           updated_at = NOW()
       WHERE id = $5`,
      ['listo', textHash, fullText.length, chunks.length, documentoId]
    );

    // 10. Actualizar palabras en tbl_libros
    await pool.query(
      'UPDATE tbl_libros SET palabras = $1 WHERE id_libro = $2',
      [palabras.length, libroId]
    );

    console.log('═'.repeat(60));
    console.log('✅ PROCESAMIENTO COMPLETADO EXITOSAMENTE');
    console.log('═'.repeat(60));
    console.log(`📖 Libro: ${libro.titulo}`);
    console.log(`📊 Estadísticas:`);
    console.log(`   - Caracteres: ${fullText.length.toLocaleString()}`);
    console.log(`   - Palabras: ${palabras.length.toLocaleString()}`);
    console.log(`   - Segmentos: ${chunks.length}`);
    console.log(`   - Hash: ${textHash.substring(0, 16)}...`);
    console.log('═'.repeat(60));

    return {
      success: true,
      libro_id: libroId,
      documento_id: documentoId,
      caracteres: fullText.length,
      palabras: palabras.length,
      segmentos: chunks.length,
    };

  } catch (error) {
    console.error('\n❌ ERROR PROCESANDO PDF:', error.message);
    
    // Intentar marcar documento como error
    try {
      await pool.query(
        'UPDATE tbl_documentos SET estado = $1, updated_at = NOW() WHERE libro_id = $2',
        ['error', libroId]
      );
    } catch (e) {
      // Ignorar error al actualizar estado
    }

    throw error;
  }
}

// Ejecutar
const libroId = parseInt(process.argv[2]) || 83;

processPdf(libroId)
  .then((result) => {
    console.log('\n🎉 Proceso finalizado exitosamente\n');
    pool.end();
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n💥 Proceso falló:', error.message);
    pool.end();
    process.exit(1);
  });
