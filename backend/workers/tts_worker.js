/**
 * Worker TTS con BullMQ
 * 
 * Procesa tareas de generación de audio en paralelo.
 * Se ejecuta como proceso independiente del backend principal.
 * 
 * Uso: node workers/tts_worker.js
 */

import { Worker } from 'bullmq';
import pkg from 'pg';
const { Pool } = pkg;
import { createClient } from '@supabase/supabase-js';
import { generateAudio, estimateDuration } from '../services/azure_tts.js';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

const redisConnection = {
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379', 10),
};

/**
 * Procesa un job de generación TTS
 */
async function processTtsJob(job) {
  const { documentId, segmentId, voiceId } = job.data;
  
  console.log(`\n[Worker TTS] 🎙️ Procesando job ${job.id}`);
  console.log(`  Documento: ${documentId}`);
  console.log(`  Segmento: ${segmentId}`);
  console.log(`  Voz: ${voiceId}`);

  try {
    // 1. Verificar si ya existe (por si otro worker lo procesó)
    const existing = await pool.query(
      'SELECT audio_url FROM tbl_audios WHERE documento_id = $1 AND segmento_id = $2 AND voz_id = $3',
      [documentId, segmentId, voiceId]
    );

    if (existing.rows.length > 0) {
      console.log(`[Worker TTS] ⏭️ Audio ya existe, saltando...`);
      return { status: 'already_exists', url: existing.rows[0].audio_url };
    }

    // 2. Obtener texto del segmento
    const segmentResult = await pool.query(
      'SELECT texto FROM tbl_segmentos WHERE id = $1',
      [segmentId]
    );

    if (segmentResult.rows.length === 0) {
      throw new Error(`Segmento ${segmentId} no encontrado`);
    }

    // 3. Obtener configuración de voz
    const voiceResult = await pool.query(
      'SELECT codigo_voz, configuracion FROM tbl_voces WHERE id = $1',
      [voiceId]
    );

    if (voiceResult.rows.length === 0) {
      throw new Error(`Voz ${voiceId} no encontrada`);
    }

    const texto = segmentResult.rows[0].texto;
    const voiceCode = voiceResult.rows[0].codigo_voz;
    const config = voiceResult.rows[0].configuracion || {};

    // 4. Generar audio
    console.log(`[Worker TTS] 🎵 Generando audio con ${voiceCode}...`);
    const audioBuffer = await generateAudio(texto, voiceCode, config);
    const durationMs = estimateDuration(texto, config.rate);

    // 5. Subir a Supabase Storage
    const fileName = `tts/${documentId}/${voiceId}/${segmentId}.mp3`;
    console.log(`[Worker TTS] ☁️ Subiendo a Storage: ${fileName}`);

    const { error: uploadError } = await supabase.storage
      .from('audios_tts')
      .upload(fileName, audioBuffer, {
        contentType: 'audio/mpeg',
        upsert: true,
      });

    if (uploadError) {
      throw new Error(`Error subiendo audio: ${uploadError.message}`);
    }

    // 6. Obtener URL pública
    const { data: urlData } = supabase.storage
      .from('audios_tts')
      .getPublicUrl(fileName);

    const audioUrl = urlData.publicUrl;

    // 7. Guardar en BD
    await pool.query(
      `INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, sample_rate, last_access_at, access_count)
       VALUES ($1, $2, $3, $4, $5, 24000, NOW(), 0)
       ON CONFLICT (documento_id, segmento_id, voz_id) 
       DO UPDATE SET audio_url = EXCLUDED.audio_url, duracion_ms = EXCLUDED.duracion_ms`,
      [documentId, segmentId, voiceId, audioUrl, durationMs]
    );

    console.log(`[Worker TTS] ✅ Audio generado: ${audioUrl}`);
    console.log(`[Worker TTS] ⏱️ Duración estimada: ${durationMs}ms\n`);

    return {
      status: 'success',
      url: audioUrl,
      durationMs,
    };
  } catch (error) {
    console.error(`[Worker TTS] ❌ Error procesando job:`, error);
    throw error; // BullMQ reintentará automáticamente
  }
}

// Crear worker con concurrencia de 6 (genera 6 audios en paralelo)
const worker = new Worker('tts-queue', processTtsJob, {
  connection: redisConnection,
  concurrency: 6,
  limiter: {
    max: 10, // máximo 10 jobs por segundo
    duration: 1000,
  },
  removeOnComplete: { count: 100 }, // mantener últimos 100 completados
  removeOnFail: { count: 50 }, // mantener últimos 50 fallidos
});

worker.on('completed', (job) => {
  console.log(`[Worker TTS] 🎉 Job ${job.id} completado`);
});

worker.on('failed', (job, err) => {
  console.error(`[Worker TTS] 💥 Job ${job?.id} falló:`, err.message);
});

worker.on('error', (err) => {
  console.error('[Worker TTS] ⚠️ Worker error:', err);
});

console.log('🚀 [Worker TTS] Iniciado con concurrencia 6');
console.log(`📡 [Worker TTS] Conectado a Redis: ${redisConnection.host}:${redisConnection.port}\n`);

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('\n[Worker TTS] Recibido SIGTERM, cerrando...');
  await worker.close();
  await pool.end();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('\n[Worker TTS] Recibido SIGINT, cerrando...');
  await worker.close();
  await pool.end();
  process.exit(0);
});
