import 'dotenv/config';
import pkg from 'pg';
const { Pool } = pkg;
import { createClient } from '@supabase/supabase-js';
import { generateAudio, estimateDuration } from './services/tts_provider.js';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function main(libroId) {
  if (!libroId) { console.error('Usage: node test_force_tts.js <libroId>'); process.exit(1); }
  console.log('Libro:', libroId);
  const docRes = await pool.query('SELECT id FROM tbl_documentos WHERE libro_id = $1 ORDER BY updated_at DESC LIMIT 1', [libroId]);
  if (!docRes.rows.length) { console.error('No document for book'); process.exit(1); }
  const docId = docRes.rows[0].id;
  const voiceRes = await pool.query('SELECT id, codigo_voz, configuracion FROM tbl_voces WHERE activo = true LIMIT 1');
  if (!voiceRes.rows.length) { console.error('No active voices'); process.exit(1); }
  const voice = voiceRes.rows[0];
  const segRes = await pool.query(`SELECT s.id, s.orden, s.texto FROM tbl_segmentos s
    LEFT JOIN tbl_audios a ON a.segmento_id = s.id AND a.voz_id = $2
    WHERE s.documento_id = $1 AND s.orden > 0 AND a.id IS NULL
    ORDER BY s.orden LIMIT 1`, [docId, voice.id]);
  if (!segRes.rows.length) { console.log('No missing segment, nothing to do.'); process.exit(0); }
  const seg = segRes.rows[0];
  console.log('Generating segment orden', seg.orden, 'voice', voice.codigo_voz);
  const audioBuffer = await generateAudio(seg.texto, voice.codigo_voz, voice.configuracion || {});
  const fileName = `libro_${libroId}/segmento_${seg.orden}.mp3`;
  console.log('Uploading to audios_tts:', fileName);
  const { error: upErr } = await supabase.storage.from('audios_tts').upload(fileName, audioBuffer, { contentType: 'audio/mpeg', upsert: true});
  if (upErr) { console.error('Upload error:', upErr); process.exit(1);} 
  const { data: urlData } = supabase.storage.from('audios_tts').getPublicUrl(fileName);
  const url = urlData.publicUrl;
  console.log('Public URL:', url);
  const dur = estimateDuration(seg.texto, (voice.configuracion||{}).rate);
  await pool.query(`INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, last_access_at, access_count)
    VALUES ($1,$2,$3,$4,$5,NOW(),1)
    ON CONFLICT (documento_id, segmento_id, voz_id) DO UPDATE SET audio_url = EXCLUDED.audio_url, duracion_ms = EXCLUDED.duracion_ms`,
    [docId, seg.id, voice.id, url, dur]);
  console.log('✅ Inserted tbl_audios row');
  process.exit(0);
}

main(parseInt(process.argv[2],10)).catch(e=>{ console.error('❌ Error:', e.message); process.exit(1); });
