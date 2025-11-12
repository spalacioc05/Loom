import 'dotenv/config';
import pkg from 'pg';
const { Pool } = pkg;
import { createClient } from '@supabase/supabase-js';
import { generateAudio, estimateDuration } from './services/tts_provider.js';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

/**
 * Genera los primeros 3 segmentos de TODOS los libros que no tengan ningún audio.
 * Esto asegura inicio rápido de reproducción para cualquier libro.
 */
async function main() {
  console.log('🚀 Generando primeros 3 segmentos para todos los libros sin audios...\n');
  
  // Obtener todos los libros con documentos listos
  const librosRes = await pool.query(`
    SELECT DISTINCT l.id_libro, l.titulo, d.id as documento_id
    FROM tbl_libros l
    INNER JOIN tbl_documentos d ON d.libro_id = l.id_libro
    WHERE d.estado = 'listo'
    ORDER BY l.id_libro
  `);
  
  console.log(`Encontrados ${librosRes.rows.length} libros con documentos listos\n`);
  
  const voiceRes = await pool.query('SELECT id, codigo_voz, configuracion FROM tbl_voces WHERE activo = true LIMIT 1');
  if (!voiceRes.rows.length) {
    console.error('❌ No hay voces activas');
    process.exit(1);
  }
  const voice = voiceRes.rows[0];
  console.log(`Usando voz: ${voice.codigo_voz}\n`);
  
  let librosConAudios = 0;
  let librosProcesados = 0;
  let totalGenerados = 0;
  
  for (const libro of librosRes.rows) {
    // Verificar si ya tiene algún audio
    const audioCountRes = await pool.query(
      'SELECT COUNT(*)::int as count FROM tbl_audios WHERE documento_id = $1',
      [libro.documento_id]
    );
    
    if (audioCountRes.rows[0].count > 0) {
      console.log(`⏭️  Libro ${libro.id_libro} "${libro.titulo}" ya tiene audios, saltando...`);
      librosConAudios++;
      continue;
    }
    
    console.log(`\n📖 Procesando libro ${libro.id_libro}: "${libro.titulo}"`);
    
    // Obtener primeros 3 segmentos (orden > 0 para saltar metadata)
    const segsRes = await pool.query(`
      SELECT s.id, s.orden, s.texto
      FROM tbl_segmentos s
      WHERE s.documento_id = $1 AND s.orden > 0
      ORDER BY s.orden
      LIMIT 3
    `, [libro.documento_id]);
    
    if (segsRes.rows.length === 0) {
      console.log(`⚠️  No hay segmentos para este libro`);
      continue;
    }
    
    console.log(`   Generando ${segsRes.rows.length} segmentos iniciales...`);
    
    let generados = 0;
    for (const seg of segsRes.rows) {
      try {
        console.log(`   [${generados + 1}/${segsRes.rows.length}] Segmento ${seg.orden}...`);
        
        const audioBuffer = await generateAudio(seg.texto, voice.codigo_voz, voice.configuracion || {});
        const fileName = `libro_${libro.id_libro}/segmento_${seg.orden}.mp3`;
        
        const { error: upErr } = await supabase.storage.from('audios_tts').upload(fileName, audioBuffer, { 
          contentType: 'audio/mpeg', 
          upsert: true
        });
        
        if (upErr) throw upErr;
        
        const { data: urlData } = supabase.storage.from('audios_tts').getPublicUrl(fileName);
        const url = urlData.publicUrl;
        const dur = estimateDuration(seg.texto, (voice.configuracion||{}).rate);
        
        await pool.query(`
          INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, last_access_at, access_count)
          VALUES ($1,$2,$3,$4,$5,NOW(),1)
          ON CONFLICT (documento_id, segmento_id, voz_id) DO UPDATE SET audio_url = EXCLUDED.audio_url, duracion_ms = EXCLUDED.duracion_ms
        `, [libro.documento_id, seg.id, voice.id, url, dur]);
        
        generados++;
        totalGenerados++;
        console.log(`   ✅ Segmento ${seg.orden} completado`);
        
        // Pequeña pausa entre segmentos
        await new Promise(resolve => setTimeout(resolve, 800));
        
      } catch (err) {
        console.error(`   ❌ Error en segmento ${seg.orden}:`, err.message);
      }
    }
    
    console.log(`   ✅ Libro completado: ${generados} audios generados`);
    librosProcesados++;
    
    // Pausa entre libros para evitar rate limiting
    if (librosProcesados < librosRes.rows.length - librosConAudios) {
      console.log(`   ⏸️  Pausa de 2s antes del siguiente libro...`);
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }
  
  console.log('\n' + '='.repeat(60));
  console.log('🎉 Proceso completado');
  console.log('='.repeat(60));
  console.log(`Libros con audios previos: ${librosConAudios}`);
  console.log(`Libros procesados: ${librosProcesados}`);
  console.log(`Total audios generados: ${totalGenerados}`);
  console.log('='.repeat(60));
  
  process.exit(0);
}

main().catch(e => { 
  console.error('❌ Error fatal:', e.message); 
  process.exit(1); 
});
