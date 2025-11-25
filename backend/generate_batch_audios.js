import 'dotenv/config';
import pkg from 'pg';
const { Pool } = pkg;
import { createClient } from '@supabase/supabase-js';
import { generateAudio, estimateDuration } from './services/tts_provider.js';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function main(libroId, count = 5) {
  if (!libroId) { 
    console.error('Usage: node generate_batch_audios.js <libroId> [count]'); 
    process.exit(1); 
  }
  
  console.log(`Generando ${count} audios para libro ${libroId}...\n`);
  
  const docRes = await pool.query('SELECT id FROM tbl_documentos WHERE libro_id = $1 ORDER BY updated_at DESC LIMIT 1', [libroId]);
  if (!docRes.rows.length) { console.error('No document for book'); process.exit(1); }
  const docId = docRes.rows[0].id;
  
  const voiceRes = await pool.query('SELECT id, codigo_voz, configuracion FROM tbl_voces WHERE activo = true LIMIT 1');
  if (!voiceRes.rows.length) { console.error('No active voices'); process.exit(1); }
  const voice = voiceRes.rows[0];
  
  const segRes = await pool.query(`SELECT s.id, s.orden, s.texto FROM tbl_segmentos s
    LEFT JOIN tbl_audios a ON a.segmento_id = s.id AND a.voz_id = $2
    WHERE s.documento_id = $1 AND s.orden > 0 AND a.id IS NULL
    ORDER BY s.orden LIMIT $3`, [docId, voice.id, count]);
  
  if (!segRes.rows.length) { 
    console.log('✅ No hay segmentos pendientes, todos generados.'); 
    process.exit(0); 
  }
  
  console.log(`Generando ${segRes.rows.length} segmentos con voz ${voice.codigo_voz}\n`);
  
  let generated = 0;
  let errors = 0;
  
  for (const seg of segRes.rows) {
    try {
          console.log(`[${generated + 1}/${segRes.rows.length}] Segmento ${seg.orden}...`);
          const audioBuffer = await generateAudio(seg.texto, voice.codigo_voz, voice.configuracion || {});
          // Definir fileName solo una vez, usando la convención con voz
  const safeVoice = (voice.codigo_voz || 'voz').replace(/[^a-zA-Z0-9_-]/g, '_');
          const fileName = `libro_${libroId}/voz_${safeVoice}/segmento_${seg.orden}.mp3`;
  const { error: upErr } = await supabase.storage.from('audios_tts').upload(fileName, audioBuffer, { 
        contentType: 'audio/mpeg', 
        upsert: true
      });
      
      if (upErr) throw upErr;
      
      const { data: urlData } = supabase.storage.from('audios_tts').getPublicUrl(fileName);
      const url = urlData.publicUrl;
      const dur = estimateDuration(seg.texto, (voice.configuracion||{}).rate);
      
      await pool.query(`INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, last_access_at, access_count)
        VALUES ($1,$2,$3,$4,$5,NOW(),1)
        ON CONFLICT (documento_id, segmento_id, voz_id) DO UPDATE SET audio_url = EXCLUDED.audio_url, duracion_ms = EXCLUDED.duracion_ms`,
        [docId, seg.id, voice.id, url, dur]);
      
      generated++;
      console.log(`✅ Segmento ${seg.orden} completado\n`);
      
      // Pausa breve para evitar rate limiting
      await new Promise(resolve => setTimeout(resolve, 1000));
      
    } catch (err) {
      errors++;
      console.error(`❌ Error en segmento ${seg.orden}:`, err.message, '\n');
    }
  }
  
  console.log('\n=== Resumen ===');
  console.log(`✅ Generados: ${generated}`);
  console.log(`❌ Errores: ${errors}`);
  
  process.exit(0);
}

const libroId = parseInt(process.argv[2], 10);
const count = parseInt(process.argv[3], 10) || 5;
main(libroId, count).catch(e => { console.error('❌ Error:', e.message); process.exit(1); });
