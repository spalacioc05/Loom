import pkg from 'pg';
const { Pool } = pkg;
import { createClient } from '@supabase/supabase-js';
import { generateAudio, estimateDuration } from '../services/tts_provider.js';

// Asegurar duración en ms como entero finito
function safeDurationMs(text, rate) {
  const ms = estimateDuration(text, rate);
  if (Number.isFinite(ms) && ms >= 0) return Math.round(ms);
  return 0;
}
import { enqueueBatch } from '../services/tts_queue.js';
import { processPdf } from '../workers/process_pdf.js';
import redisCache from '../services/redis_cache.js';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: parseInt(process.env.PG_POOL_MAX || '8', 10),
  idleTimeoutMillis: 30000,
  ssl: process.env.PG_DISABLE_SSL === 'true' ? false : { rejectUnauthorized: false },
});

pool.on('error', (err) => {
  console.error('[PG Pool] Unexpected error on idle client:', err.message);
});

// Control simple en memoria para evitar generación concurrente duplicada de mismos segmentos
const activeGenerations = new Set(); // keys: documentoId:vozId

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

// Utilidades para clasificar voces GCP
function getStyleFromVoiceCode(code) {
  if (!code) return 'Standard';
  if (code.includes('Neural2')) return 'Neural2';
  if (code.includes('Wavenet')) return 'Wavenet';
  if (code.includes('Studio')) return 'Studio';
  return 'Standard';
}

function getGenderFromVoiceCode(code) {
  if (!code) return 'NEUTRAL';
  const last = code.charAt(code.length - 1).toUpperCase();
  if (['A', 'C', 'E'].includes(last)) return 'FEMALE';
  if (['B', 'D', 'F'].includes(last)) return 'MALE';
  return 'NEUTRAL';
}

// Retry helper for transient operations (async function)
async function retryAsync(fn, attempts = 2, delayMs = 500) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      console.warn(`[Retry] intento ${i + 1} falló: ${err.message || err}`);
      if (i < attempts - 1) await new Promise(r => setTimeout(r, delayMs));
    }
  }
  throw lastErr;
}

// GET /voices - Listar voces disponibles (solo GCP, condensadas por idioma+estilo con M/F)
const getVoices = async (req, res) => {
  try {
    // Intentar obtener del cache primero
    const cacheKey = 'voices:all';
    const cached = await redisCache.client?.get(cacheKey).catch(() => null);
    
    if (cached) {
      console.log('🚀 [Redis Cache] ✅ Voces respondidas desde CACHE (instantáneo)');
      return res.json(JSON.parse(cached));
    }
    
    console.log('[Voices] 📊 Cache miss - consultando PostgreSQL...');

    let query = `SELECT id, proveedor, codigo_voz, idioma, configuracion, activo FROM tbl_voces WHERE proveedor = 'gcp' AND activo = true ORDER BY idioma, codigo_voz`;
    let result;
    try {
      result = await pool.query(query);
    } catch (err) {
      // Si la columna id no existe (migración incompleta), intentamos sin id
      if (/(column \"id\" does not exist)/i.test(err.message)) {
        console.warn('[Voices] Columna id ausente, usando fallback sin id. Revisa migración de tbl_voces.');
        result = await pool.query(`SELECT proveedor, codigo_voz, idioma, configuracion, activo FROM tbl_voces WHERE proveedor = 'gcp' AND activo = true ORDER BY idioma, codigo_voz`);
      } else {
        throw err;
      }
    }

    // Construir lista condensada: por (lang, style) elegir 1 femenina y 1 masculina si existen
    const rawVoices = result.rows.map((row, idx) => ({
      id: row.id || `${row.proveedor}:${row.codigo_voz}:${idx}`,
      provider: row.proveedor,
      voice_code: row.codigo_voz,
      lang: row.idioma,
      settings_json: row.configuracion,
      active: row.activo,
      style: getStyleFromVoiceCode(row.codigo_voz),
      gender: getGenderFromVoiceCode(row.codigo_voz)
    }));

    // Agrupar por (idioma|estilo) y seleccionar como máximo 1 femenina y 1 masculina.
    // Mantener neutrales como fallback si falta alguno de los dos géneros.
    const grouped = new Map(); // key: `${lang}|${style}` -> { female?: voice, male?: voice, neutrals: [] }
    for (const v of rawVoices) {
      const key = `${v.lang}|${v.style}`;
      if (!grouped.has(key)) grouped.set(key, { female: null, male: null, neutrals: [] });
      const entry = grouped.get(key);
      if (v.gender === 'FEMALE' && !entry.female) entry.female = v;
      else if (v.gender === 'MALE' && !entry.male) entry.male = v;
      else entry.neutrals.push(v);
    }

    // Usar neutrales como fallback si falta femenino o masculino (sin duplicar la misma voz)
    for (const [key, entry] of grouped.entries()) {
      if (!entry.female && entry.neutrals.length > 0) {
        // Tomar la primera neutral disponible como femenina si no existe
        entry.female = entry.neutrals.shift();
      }
      if (!entry.male && entry.neutrals.length > 0) {
        // Tomar la siguiente neutral disponible como masculina si no existe
        entry.male = entry.neutrals.shift();
      }
    }

    // Aplanar resultados en orden por idioma y estilo
    const voices = [];
    const sorter = (a, b) => String(a).localeCompare(String(b));
    const keysSorted = Array.from(grouped.keys()).sort(sorter);
    for (const key of keysSorted) {
      const [lang, style] = key.split('|');
      const entry = grouped.get(key);
      if (entry.female) {
        voices.push({
          id: entry.female.id,
          provider: entry.female.provider,
          voice_code: entry.female.voice_code,
          lang,
          style,
          gender: 'FEMALE',
          settings_json: entry.female.settings_json,
          active: entry.female.active,
        });
      }
      if (entry.male) {
        voices.push({
          id: entry.male.id,
          provider: entry.male.provider,
          voice_code: entry.male.voice_code,
          lang,
          style,
          gender: 'MALE',
          settings_json: entry.male.settings_json,
          active: entry.male.active,
        });
      }
    }

    if (!voices.length) {
      console.warn('[Voices] No se encontraron voces activas. Verifica inserciones en migración.');
    }

    // Cachear voces por 24 horas
    await redisCache.client?.setex(cacheKey, 60 * 60 * 24, JSON.stringify(voices)).catch(() => {});
    console.log('💾 [Redis Cache] Voces cacheadas (TTL: 24h)');

    res.json(voices);
  } catch (error) {
    console.error('[Voices] Error obteniendo voces:', error.message);
    res.status(500).json({ error: 'Error obteniendo voces', detail: error.message });
  }
};

// POST /api/tts/playlist - Generar playlist de segmentos
// Body: { document_id?, libro_id?, voice_id, from_offset_char?, start_segment_id?, preferExisting?, generateFirstIfMissing? }
const getPlaylist = async (req, res) => {
  try {
    let { document_id, libro_id, voice_id, from_offset_char, start_segment_id, preferExisting, generateFirstIfMissing } = req.body;

    if (!document_id && !libro_id) {
      return res.status(400).json({ error: 'Debes enviar document_id (UUID) o libro_id' });
    }
    if (!voice_id) {
      return res.status(400).json({ error: 'voice_id es requerido' });
    }

    // Si viene libro_id, resolver a document_id
    if (!document_id && libro_id) {
      const docByBook = await pool.query(
        `SELECT id, estado
         FROM tbl_documentos
         WHERE libro_id = $1
         ORDER BY updated_at DESC
         LIMIT 1`,
        [libro_id]
      );
      if (docByBook.rows.length === 0) {
        return res.status(404).json({ error: 'Documento no encontrado para ese libro', libro_id });
      }
      document_id = docByBook.rows[0].id;
    }

    // Verificar que el documento existe
    const docResult = await pool.query(
      'SELECT id, estado FROM tbl_documentos WHERE id = $1',
      [document_id]
    );

    if (docResult.rows.length === 0) {
      return res.status(404).json({ error: 'Documento no encontrado' });
    }

    const estadoDoc = docResult.rows[0].estado;
    // Permitir reproducción temprana si está 'procesando'; solo bloquear si está en 'error'
    if (estadoDoc === 'error') {
      return res.status(400).json({ 
        error: 'Documento en estado de error',
        estado: estadoDoc
      });
    }

    // Determinar segmento inicial por offset o usar el primero
    let startSegmentId = start_segment_id || null;
    let startIntraMs = 0;

    if (!startSegmentId && from_offset_char != null) {
      const segResult = await pool.query(
        `SELECT id FROM tbl_segmentos 
         WHERE documento_id = $1 
           AND char_inicio <= $2 
           AND char_fin > $2
         LIMIT 1`,
        [document_id, from_offset_char]
      );
      if (segResult.rows.length > 0) {
        startSegmentId = segResult.rows[0].id;
        // TODO: calcular intra_ms basado en posición dentro del segmento
      }
    }

    // Obtener primeros 5 segmentos desde el punto de inicio
    const segmentQuery = startSegmentId
      ? `SELECT s.id, s.orden, a.audio_url, a.duracion_ms
         FROM tbl_segmentos s
         LEFT JOIN tbl_audios a ON a.segmento_id = s.id AND a.voz_id = $2
         WHERE s.documento_id = $1 
           AND s.orden >= (SELECT orden FROM tbl_segmentos WHERE id = $3)
         ORDER BY s.orden
         LIMIT 5`
      : `SELECT s.id, s.orden, a.audio_url, a.duracion_ms
         FROM tbl_segmentos s
         LEFT JOIN tbl_audios a ON a.segmento_id = s.id AND a.voz_id = $2
         WHERE s.documento_id = $1
         ORDER BY s.orden
         LIMIT 5`;

    const params = startSegmentId 
      ? [document_id, voice_id, startSegmentId]
      : [document_id, voice_id];

  const segments = await pool.query(segmentQuery, params);

    const items = segments.rows.map(row => ({
      segment_id: row.id,
      url: row.audio_url || null, // null si no está generado aún
      duration_ms: row.duracion_ms || null,
    }));

    // Si se solicita, generar sincrónicamente el primer segmento si falta (para no reiniciar al cambiar voz)
    if (items.length > 0 && !items[0].url && generateFirstIfMissing) {
      const seg0 = items[0];
      const segData = await pool.query('SELECT texto, orden FROM tbl_segmentos WHERE id = $1', [seg0.segment_id]);
      const voiceData = await pool.query('SELECT codigo_voz, configuracion FROM tbl_voces WHERE id = $1', [voice_id]);
      if (segData.rows.length && voiceData.rows.length) {
        const texto = segData.rows[0].texto;
        const orden = segData.rows[0].orden;
        const vcode = voiceData.rows[0].codigo_voz;
        const vconf = voiceData.rows[0].configuracion || {};
        // Intentar generar y subir con reintentos para errores transitorios
        const { publicUrl } = await retryAsync(async () => {
          const audioBuffer = await generateAudio(texto, vcode, vconf);
          const safeVoice = (vcode || 'voz').replace(/[^a-zA-Z0-9_-]/g, '_');
          const fileName = `libro_${libroId || 'doc'}/voz_${safeVoice}/segmento_${orden}.mp3`;
          const { error: uploadError } = await supabase.storage.from('audios_tts').upload(fileName, audioBuffer, { contentType: 'audio/mpeg', upsert: true });
          if (uploadError) throw uploadError;
          const { data: urlData } = supabase.storage.from('audios_tts').getPublicUrl(fileName);
          return { publicUrl: urlData.publicUrl };
        }, 2, 800);

        const duracion = safeDurationMs(texto, vconf.rate);
        await pool.query(
          `INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, last_access_at, access_count)
           VALUES ($1, $2, $3, $4, $5, NOW(), 1)
           ON CONFLICT (documento_id, segmento_id, voz_id)
           DO UPDATE SET audio_url = EXCLUDED.audio_url, duracion_ms = EXCLUDED.duracion_ms, last_access_at = NOW()`,
          [document_id, seg0.segment_id, voice_id, publicUrl, duracion]
        );
        seg0.url = publicUrl;
        seg0.duration_ms = duracion;
      }
    }

    // Encolar generación de los siguientes 10 segmentos en background (precarga inteligente)
    if (items.length > 0 && !preferExisting) {
      const firstSegmentOrder = await pool.query(
        'SELECT orden FROM tbl_segmentos WHERE id = $1',
        [items[0].segment_id]
      );
      
      if (firstSegmentOrder.rows.length > 0) {
        const startOrder = firstSegmentOrder.rows[0].orden;
        
        // Obtener siguientes 10 segmentos para encolar
        const nextSegments = await pool.query(
          `SELECT s.id 
           FROM tbl_segmentos s
           LEFT JOIN tbl_audios a ON a.segmento_id = s.id AND a.voz_id = $2
           WHERE s.documento_id = $1 
             AND s.orden > $3
             AND a.id IS NULL
           ORDER BY s.orden
           LIMIT 10`,
          [document_id, voice_id, startOrder]
        );
        
        if (nextSegments.rows.length > 0) {
          const segmentIds = nextSegments.rows.map(r => r.id);
          // Encolar en background (sin await para no bloquear respuesta)
          enqueueBatch(document_id, segmentIds, voice_id, { basePriority: 20 })
            .catch(err => console.error('[Playlist] Error encolando batch:', err));
          console.log(`[Playlist] 📦 Encolados ${segmentIds.length} segmentos para precarga`);
        }
      }
    }

    res.json({
      document_id,
      voice_id,
      estado: estadoDoc,
      items,
      start_segment_id: items.length > 0 ? items[0].segment_id : null,
      start_intra_ms: startIntraMs,
    });
  } catch (error) {
    console.error('Error generando playlist:', error);
    res.status(500).json({ error: 'Error generando playlist' });
  }
};

// GET /api/tts/segment?doc=...&voice=...&segment=... (o ?libro=...&voice=...)
// Devuelve o genera el audio para un segmento específico
const getSegmentAudio = async (req, res) => {
  try {
    let { doc, libro, voice, segment } = req.query;

    if (!doc && libro) {
      const docByBook = await pool.query(
        `SELECT id FROM tbl_documentos 
         WHERE libro_id = $1 
         ORDER BY updated_at DESC LIMIT 1`,
        [libro]
      );
      if (docByBook.rows.length > 0) {
        doc = docByBook.rows[0].id;
      }
    }

    if (!doc || !voice || !segment) {
      return res.status(400).json({ error: 'Parámetros doc (o libro), voice y segment son requeridos' });
    }

    // Buscar audio en cache
    const cacheResult = await pool.query(
      `SELECT id, audio_url FROM tbl_audios 
       WHERE documento_id = $1 AND voz_id = $2 AND segmento_id = $3`,
      [doc, voice, segment]
    );

    if (cacheResult.rows.length > 0) {
      console.log(`[TTS] ✅ Audio cacheado encontrado para segmento ${segment}`);
      
      // Actualizar last_access_at y contador (sin await para no bloquear respuesta)
      pool.query(
        `UPDATE tbl_audios 
         SET last_access_at = NOW(), 
             access_count = access_count + 1 
         WHERE id = $1`,
        [cacheResult.rows[0].id]
      ).catch(err => console.error('[TTS] Error actualizando access:', err));
      
      // Redirigir a URL del audio cacheado
      return res.redirect(cacheResult.rows[0].audio_url);
    }

    console.log(`[TTS] ⚙️ Audio no cacheado, generando para segmento ${segment}...`);

    // Obtener datos del segmento y voz
    const segmentData = await pool.query(
      'SELECT texto FROM tbl_segmentos WHERE id = $1',
      [segment]
    );

    if (segmentData.rows.length === 0) {
      return res.status(404).json({ error: 'Segmento no encontrado' });
    }

    const voiceData = await pool.query(
      'SELECT codigo_voz, configuracion FROM tbl_voces WHERE id = $1',
      [voice]
    );

    if (voiceData.rows.length === 0) {
      return res.status(404).json({ error: 'Voz no encontrada' });
    }

    const texto = segmentData.rows[0].texto;
    const voiceCode = voiceData.rows[0].codigo_voz;
    const config = voiceData.rows[0].configuracion || {};

    // Generar audio con Azure TTS
    console.log(`[TTS] Generando con voz: ${voiceCode}`);
    const audioBuffer = await generateAudio(texto, voiceCode, config);
    const durationMs = safeDurationMs(texto, config.rate);

    // Subir a Supabase Storage
    const fileName = `tts/${doc}/${voice}/${segment}.mp3`;
    console.log(`[TTS] Subiendo a Supabase Storage: ${fileName}`);
    
    const { data: uploadData, error: uploadError } = await supabase.storage
      .from('audios_tts')
      .upload(fileName, audioBuffer, { 
        contentType: 'audio/mpeg',
        upsert: true 
      });

    if (uploadError) {
      console.error('[TTS] ❌ Error subiendo audio:', uploadError);
      return res.status(500).json({ error: 'Error subiendo audio a storage' });
    }

    // Obtener URL pública
    const { data: urlData } = supabase.storage
      .from('audios_tts')
      .getPublicUrl(fileName);

    const audioUrl = urlData.publicUrl;
    console.log(`[TTS] ✅ Audio generado y subido: ${audioUrl}`);

    // Guardar en cache (BD)
    await pool.query(
      `INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, last_access_at, access_count)
       VALUES ($1, $2, $3, $4, $5, NOW(), 1)
       ON CONFLICT (documento_id, segmento_id, voz_id) DO UPDATE 
       SET audio_url = EXCLUDED.audio_url, 
           duracion_ms = EXCLUDED.duracion_ms,
           last_access_at = NOW(),
           access_count = tbl_audios.access_count + 1`,
      [doc, segment, voice, audioUrl, durationMs]
    );

    // Redirigir al audio generado
    res.redirect(audioUrl);
  } catch (error) {
    console.error('[TTS] ❌ Error obteniendo/generando audio:', error);
    res.status(500).json({ error: 'Error generando audio', details: error.message });
  }
};

// POST /api/progress - Guardar progreso de reproducción
// Body: { document_id, voice_id, segment_id, intra_ms, global_offset_char? }
const saveProgress = async (req, res) => {
  try {
    const { document_id, voice_id, segment_id, intra_ms, global_offset_char } = req.body;
    const headerUser = req.headers['x-user-id'];
    const userIdNum = headerUser ? Number(headerUser) : null;

    if (!document_id || !voice_id || segment_id == null || intra_ms == null) {
      return res.status(400).json({ 
        error: 'document_id, voice_id, segment_id e intra_ms son requeridos' 
      });
    }

    // Guardar progreso directamente en tbl_libros_x_usuarios (no usamos tbl_progreso)
    if (userIdNum && Number.isFinite(userIdNum)) {
      try {
        const docRes = await pool.query('SELECT libro_id FROM tbl_documentos WHERE id = $1 LIMIT 1', [document_id]);
        if (docRes.rows.length > 0) {
          const libroId = docRes.rows[0].libro_id;
          
          // Calcular progreso real: (segmento_actual / total_segmentos) * 100
          const totalSegsRes = await pool.query(
            'SELECT COUNT(*) as total FROM tbl_segmentos WHERE documento_id = $1',
            [document_id]
          );
          const totalSegmentos = parseInt(totalSegsRes.rows[0]?.total || 0);
          
          // Calcular porcentaje (segmento_id es 1-indexed normalmente)
          let porcentajeProgreso = 1; // mínimo 1%
          if (totalSegmentos > 0) {
            porcentajeProgreso = Math.min(100, Math.round((segment_id / totalSegmentos) * 100));
          }
          
          await pool.query(
            `INSERT INTO tbl_libros_x_usuarios (id_usuario, id_libro, fecha_ultima_lectura, progreso, tiempo_escucha)
             VALUES ($1, $2, NOW(), $3, 0)
             ON CONFLICT (id_usuario, id_libro)
             DO UPDATE SET 
               fecha_ultima_lectura = NOW(),
               progreso = GREATEST(tbl_libros_x_usuarios.progreso, $3)`,
            [userIdNum, libroId, porcentajeProgreso]
          );
          
          console.log(`✅ Progreso guardado: Usuario ${userIdNum}, Libro ${libroId}, ${porcentajeProgreso}%`);
        }
      } catch (e) {
        console.error('[Progreso] Error actualizando biblioteca:', e.message);
        return res.status(500).json({ error: 'Error guardando progreso', detail: e.message });
      }
    } else {
      console.warn('[Progreso] No se recibió id_usuario válido, no se guardó progreso');
    }

    res.json({ success: true });
  } catch (error) {
    console.error('Error guardando progreso:', error);
    res.status(500).json({ error: 'Error guardando progreso' });
  }
};

// GET /api/progress?doc=... - Obtener último progreso
const getProgress = async (req, res) => {
  try {
    const { doc } = req.query;
    const headerUser = req.headers['x-user-id'];
    const userIdNum = headerUser ? Number(headerUser) : null;

    if (!doc) {
      return res.status(400).json({ error: 'Parámetro doc es requerido' });
    }

    if (!userIdNum || !Number.isFinite(userIdNum)) {
      return res.json(null); // Sin usuario válido, sin progreso
    }

    // Obtener progreso desde tbl_libros_x_usuarios
    const docRes = await pool.query('SELECT libro_id FROM tbl_documentos WHERE id = $1 LIMIT 1', [doc]);
    if (docRes.rows.length === 0) {
      return res.json(null);
    }

    const libroId = docRes.rows[0].libro_id;
    const result = await pool.query(
      `SELECT progreso FROM tbl_libros_x_usuarios
       WHERE id_usuario = $1 AND id_libro = $2
       LIMIT 1`,
      [userIdNum, libroId]
    );

    if (result.rows.length === 0) {
      return res.json(null);
    }

    const prog = result.rows[0];
    res.json({
      document_id: doc,
      progress_percent: prog.progreso || 0
    });
  } catch (error) {
    console.error('Error obteniendo progreso:', error);
    res.status(500).json({ error: 'Error obteniendo progreso' });
  }
};

// GET /api/tts/libro/:libroId/audios - Obtener todas las URLs de audio de un libro
const getBookAudios = async (req, res) => {
  try {
    const startTime = Date.now();
    const { libroId } = req.params;
    const { autoGenerate, voiceId } = req.query; // ?autoGenerate=5|all&voiceId=uuid
    // autoGenerate:
    //   omitido -> no generar
    //   número  -> generar primeros N faltantes
    //   'all'|'full' -> generar TODOS los faltantes en background

    if (!libroId) {
      return res.status(400).json({ error: 'libroId es requerido' });
    }

    console.log(`\n📚 [BookAudios] Libro ${libroId}, autoGen=${autoGenerate}, voiceId=${voiceId?.substring(0, 8)}...`);

    // Si no se solicita auto-generación, intentar obtener del cache
    if (!autoGenerate && voiceId) {
      const cachedList = await redisCache.getBookAudiosList(libroId, voiceId);
      if (cachedList) {
        console.log(`[BookAudios] ✅ Respondiendo desde cache (${cachedList.length} audios)`);
        return res.json(cachedList);
      }
    }

    console.log(`[BookAudios] Consultando BD...`);

    // Obtener documento_id del libro
    let docResult = await pool.query(
      'SELECT id, estado FROM tbl_documentos WHERE libro_id = $1 ORDER BY created_at DESC LIMIT 1',
      [libroId]
    );

    let documentoId = null;
    let estado = null;

    if (docResult.rows.length === 0) {
      console.log(`[BookAudios] 📄 No existe documento para libro ${libroId}. Iniciando segmentación...`);
      // Intentar obtener PDF del libro y procesarlo en background
      (async () => {
        try {
          await processPdf(parseInt(libroId, 10));
          console.log(`[BookAudios] ✅ Segmentación inicial disparada para libro ${libroId}`);
        } catch (e) {
          console.error(`[BookAudios] ❌ Error segmentando libro ${libroId}:`, e.message);
        }
      })();
      return res.json({
        libro_id: parseInt(libroId, 10),
        documento_id: null,
        estado: 'procesando',
        total_segmentos: 0,
        audios_generados: 0,
        progreso_porcentaje: 0,
        audios: [],
        message: 'Segmentación iniciada. Reintenta en unos segundos.'
      });
    } else {
      documentoId = docResult.rows[0].id;
      estado = docResult.rows[0].estado;
    }
    // Permitir respuesta incluso si está 'procesando' para habilitar polling y generación temprana
    if (estado === 'error') {
      return res.status(400).json({ 
        error: 'Documento en estado de error',
        estado 
      });
    }

    // Usar voz especificada o la primera por defecto
    let vozId, voiceCode, voiceConfig;
    if (voiceId) {
      const vozResult = await pool.query(
        'SELECT id, codigo_voz, configuracion FROM tbl_voces WHERE id = $1 AND activo = true',
        [voiceId]
      );
      if (vozResult.rows.length === 0) {
        return res.status(404).json({ error: 'Voz no encontrada' });
      }
      vozId = vozResult.rows[0].id;
      voiceCode = vozResult.rows[0].codigo_voz;
      voiceConfig = vozResult.rows[0].configuracion || {};
    } else {
      // Intentar seleccionar por defecto: preferir explicitamente 'es-ES-Wavenet-E' si existe
      let vozResult = await pool.query(
        `SELECT id, codigo_voz, configuracion FROM tbl_voces
         WHERE proveedor = 'gcp' AND activo = true AND codigo_voz = 'es-ES-Wavenet-E' LIMIT 1`
      );

      // Si no existe, seguir con la heurística previa: GCP femenina español
      if (vozResult.rows.length === 0) {
        vozResult = await pool.query(
          `SELECT id, codigo_voz, configuracion FROM tbl_voces
           WHERE proveedor = 'gcp' AND activo = true AND codigo_voz LIKE 'es-%' AND substring(codigo_voz from '.{1}$') IN ('A','C','E')
           LIMIT 1`
        );
      }

      // Si no se encontró, buscar cualquier GCP femenina
      if (vozResult.rows.length === 0) {
        vozResult = await pool.query(
          `SELECT id, codigo_voz, configuracion FROM tbl_voces
           WHERE proveedor = 'gcp' AND activo = true AND substring(codigo_voz from '.{1}$') IN ('A','C','E')
           LIMIT 1`
        );
      }

      // Si todavía no hay, tomar cualquier GCP activa
      if (vozResult.rows.length === 0) {
        vozResult = await pool.query(
          `SELECT id, codigo_voz, configuracion FROM tbl_voces
           WHERE proveedor = 'gcp' AND activo = true
           LIMIT 1`
        );
      }

      // Fallback: cualquier voz activa
      if (vozResult.rows.length === 0) {
        const fallback = await pool.query(
          'SELECT id, codigo_voz, configuracion FROM tbl_voces WHERE activo = true LIMIT 1'
        );
        if (fallback.rows.length === 0) {
          return res.status(500).json({ error: 'No hay voces configuradas' });
        }
        vozResult = fallback;
      }

      vozId = vozResult.rows[0].id;
      voiceCode = vozResult.rows[0].codigo_voz;
      voiceConfig = vozResult.rows[0].configuracion || {};
    }

    // Obtener todos los segmentos con sus audios (SALTAR segmento 0 = metadata)
    const audiosResult = await pool.query(
      `SELECT 
        s.id as segmento_id,
        s.orden,
        s.texto,
        a.audio_url,
        a.duracion_ms
       FROM tbl_segmentos s
       LEFT JOIN tbl_audios a ON a.segmento_id = s.id AND a.voz_id = $2
       WHERE s.documento_id = $1 AND s.orden >= 0
       ORDER BY s.orden ASC`,
      [documentoId, vozId]
    );

    if (audiosResult.rows.length === 0) {
      // Si aún no hay segmentos (p.ej. segmentación inicial), devolver 200 con lista vacía para permitir polling en el cliente
      return res.json({
        libro_id: parseInt(libroId),
        documento_id: documentoId,
        estado,
        total_segmentos: 0,
        audios_generados: 0,
        progreso_porcentaje: 0,
        audios: []
      });
    }

    const audios = audiosResult.rows.map(row => ({
      segmento_id: row.segmento_id,
      orden: row.orden,
      audio_url: row.audio_url,
      duracion_ms: row.duracion_ms || 0,
      texto_preview: row.texto ? row.texto.substring(0, 100) : null
    }));

    // Si autoGenerate está activado, generar los primeros N audios faltantes en background
    // ESTRATEGIA: Generar SIEMPRE los siguientes 20 audios para mantener buffer fluido
    const wantsFull = typeof autoGenerate === 'string' && /^(all|full|todos)$/i.test(autoGenerate);
    const numericGenerate = !wantsFull && autoGenerate && !isNaN(parseInt(autoGenerate, 10)) ? parseInt(autoGenerate, 10) : 0;

    if (wantsFull || numericGenerate > 0) {
      const sinAudio = audiosResult.rows.filter(row => !row.audio_url);
      if (sinAudio.length > 0) {
        const faltantes = wantsFull ? sinAudio : sinAudio.slice(0, numericGenerate);
        console.log(`[BookAudios] 🚀 Generación ${wantsFull ? 'completa' : 'parcial'}: ${faltantes.length} segmentos (faltaban ${sinAudio.length}).`);
        const genKey = `${documentoId}:${vozId}`;
        if (activeGenerations.has(genKey)) {
          console.log(`[BookAudios] ⏭️ Ya hay una generación activa para ${genKey}, omitiendo duplicado.`);
        } else {
          activeGenerations.add(genKey);
          (async () => {
          let generados = 0;
          let errores = 0;
          const safeVoice = (voiceCode || 'voz').replace(/[^a-zA-Z0-9_-]/g, '_');
          for (const seg of faltantes) {
            try {
              const segStartTime = Date.now();
              const audioBuffer = await generateAudio(seg.texto, voiceCode, voiceConfig);
              const fileName = `libro_${libroId}/voz_${safeVoice}/segmento_${seg.orden}.mp3`;
              const { error: uploadError } = await supabase.storage
                .from('audios_tts')
                .upload(fileName, audioBuffer, { contentType: 'audio/mpeg', upsert: true });
              if (uploadError) throw uploadError;
              const { data: urlData } = supabase.storage
                .from('audios_tts')
                .getPublicUrl(fileName);
              const duracion = safeDurationMs(seg.texto, voiceConfig.rate);
              await pool.query(
                `INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, last_access_at, access_count)
                 VALUES ($1, $2, $3, $4, $5, NOW(), 1)
                 ON CONFLICT (documento_id, segmento_id, voz_id)
                 DO UPDATE SET audio_url = EXCLUDED.audio_url, duracion_ms = EXCLUDED.duracion_ms, last_access_at = NOW(), access_count = tbl_audios.access_count + 1`,
                [documentoId, seg.segmento_id, vozId, urlData.publicUrl, duracion]
              );
              const elapsedSeg = ((Date.now() - segStartTime) / 1000).toFixed(1);
              console.log(`[BookAudios] ✅ Segmento ${seg.orden} (${generados + 1}/${faltantes.length}) en ${elapsedSeg}s`);
              generados++;
              // Throttle ligero
              await new Promise(r => setTimeout(r, 300));
            } catch (err) {
              console.error(`[BookAudios] ❌ Segmento ${seg.orden}: ${err.message}`);
              errores++;
            }
          }
          console.log(`[BookAudios] 🧾 Resultado generación: ${generados} OK, ${errores} errores.`);
        })()
          .catch(err => console.error('[BookAudios] Error fatal generación:', err))
          .finally(() => {
            activeGenerations.delete(genKey);
          });
        }
      }
    }

    // Contar cuántos tienen audio
    const conAudio = audios.filter(a => a.audio_url).length;
    const total = audios.length;
    const elapsed = Date.now() - startTime;

    console.log(`[BookAudios] ✅ ${conAudio}/${total} audios (${elapsed}ms) voz=${voiceCode}`);

    const response = {
      libro_id: parseInt(libroId),
      documento_id: documentoId,
      estado,
      total_segmentos: total,
      audios_generados: conAudio,
      progreso_porcentaje: Math.round((conAudio / total) * 100),
      audios,
      generation_mode: wantsFull ? 'full' : (numericGenerate > 0 ? `partial:${numericGenerate}` : 'none')
    };

    // Cachear respuesta si no se está auto-generando (datos estables)
    if (!autoGenerate && voiceId && conAudio > 0) {
      await redisCache.cacheBookAudiosList(libroId, voiceId, response).catch(() => {});
    }

    res.json(response);
  } catch (error) {
    console.error('[BookAudios] Error:', error);
    res.status(500).json({ error: 'Error obteniendo audios del libro' });
  }
};

// POST /tts/libro/:libroId/quick-start
// Genera el PRIMER audio de forma síncrona si no existe, luego inicia generación de los siguientes 3 en background
// Responde solo cuando el primer audio está listo
const quickStartBook = async (req, res) => {
  try {
    const { libroId } = req.params;
    const { voiceId, nextCount } = req.body;

    if (!libroId || !voiceId) {
      return res.status(400).json({ error: 'libroId y voiceId son requeridos' });
    }

    const followCount = (typeof nextCount === 'number' && nextCount > 0 && nextCount < 100) ? nextCount : 3;
    console.log(`\n🚀 [QuickStart] Libro ${libroId}, Voz ${voiceId}, nextCount=${followCount}`);

    // 1. Obtener documento del libro
    const docResult = await pool.query(
      `SELECT id, estado FROM tbl_documentos WHERE libro_id = $1 ORDER BY updated_at DESC LIMIT 1`,
      [libroId]
    );

    if (docResult.rows.length === 0) {
      // Si no existe documento aún, disparar segmentación en background y responder 202
      (async () => {
        try {
          await processPdf(parseInt(libroId, 10));
          console.log(`[QuickStart] Segmentación encolada para libro ${libroId}`);
        } catch (e) {
          console.error(`[QuickStart] Error encolando segmentación para libro ${libroId}:`, e.message || e);
        }
      })();
      return res.status(202).json({ message: 'Documento/segmentos no listos. Segmentación iniciada. Reintenta en unos segundos.' });
    }

    const documentoId = docResult.rows[0].id;
    const estado = docResult.rows[0].estado;

    if (estado === 'error') {
      return res.status(400).json({ error: 'El documento está en estado de error' });
    }

    // 2. Obtener el PRIMER segmento (orden >= 0, todos los segmentos)
    const firstSegResult = await pool.query(
      `SELECT s.id, s.orden, s.texto 
       FROM tbl_segmentos s
       WHERE s.documento_id = $1 AND s.orden >= 0
       ORDER BY s.orden ASC
       LIMIT 1`,
      [documentoId]
    );

    if (firstSegResult.rows.length === 0) {
      // No hay segmentos aún: lanzar segmentación en background y devolver 202
      (async () => {
        try {
          await processPdf(parseInt(libroId, 10));
          console.log(`[QuickStart] Segmentación encolada (no había segmentos) para libro ${libroId}`);
        } catch (e) {
          console.error(`[QuickStart] Error encolando segmentación para libro ${libroId}:`, e.message || e);
        }
      })();
      return res.status(202).json({ message: 'No hay segmentos todavía. Segmentación iniciada. Reintenta en unos segundos.' });
    }

    const firstSegment = firstSegResult.rows[0];
    console.log(`   Primer segmento: orden ${firstSegment.orden}, ${firstSegment.texto.length} caracteres`);

    // 3. Verificar si ya existe el audio del primer segmento
    const existingAudio = await pool.query(
      `SELECT audio_url FROM tbl_audios 
       WHERE documento_id = $1 AND segmento_id = $2 AND voz_id = $3`,
      [documentoId, firstSegment.id, voiceId]
    );

    let firstAudioUrl;

    if (existingAudio.rows.length > 0) {
      console.log(`   ✅ Primer audio ya existe`);
      firstAudioUrl = existingAudio.rows[0].audio_url;
    } else {
      // 4. Generar el primer audio SINCRÓNICAMENTE
      console.log(`   ⏳ Generando primer audio...`);
      
      const voiceResult = await pool.query(
        `SELECT codigo_voz, configuracion FROM tbl_voces WHERE id = $1`,
        [voiceId]
      );

      if (voiceResult.rows.length === 0) {
        return res.status(404).json({ error: 'Voz no encontrada' });
      }

      const voice = voiceResult.rows[0];
      
      try {
        // Generar audio
        // Generar y subir con reintentos en caso de fallos transitorios
        const { publicUrl } = await retryAsync(async () => {
          const audioBuffer = await generateAudio(
            firstSegment.texto,
            voice.codigo_voz,
            voice.configuracion || {}
          );
          // Subir a Supabase Storage
          const safeVoice = (voice.codigo_voz || 'voz').replace(/[^a-zA-Z0-9_-]/g, '_');
          const fileName = `libro_${libroId}/voz_${safeVoice}/segmento_${firstSegment.orden}.mp3`;
          const { error: uploadError } = await supabase.storage
            .from('audios_tts')
            .upload(fileName, audioBuffer, {
              contentType: 'audio/mpeg',
              upsert: true
            });
          if (uploadError) throw uploadError;
          const { data: urlData } = supabase.storage
            .from('audios_tts')
            .getPublicUrl(fileName);
          return { publicUrl: urlData.publicUrl };
        }, 2, 800);

        firstAudioUrl = publicUrl;

        // Estimar duración
        const duracion = safeDurationMs(firstSegment.texto, (voice.configuracion || {}).rate);

        // Guardar en BD
        await pool.query(
          `INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, last_access_at, access_count)
           VALUES ($1, $2, $3, $4, $5, NOW(), 1)
           ON CONFLICT (documento_id, segmento_id, voz_id) 
           DO UPDATE SET audio_url = EXCLUDED.audio_url, duracion_ms = EXCLUDED.duracion_ms, last_access_at = NOW()`,
          [documentoId, firstSegment.id, voiceId, firstAudioUrl, duracion]
        );

        console.log(`   ✅ Primer audio generado: ${firstAudioUrl}`);
      } catch (genError) {
        console.error(`   ❌ Error generando primer audio:`, genError);
        return res.status(500).json({ error: 'Error generando primer audio', detail: genError.message });
      }
    }

    // 5. Iniciar generación en BACKGROUND de los siguientes 'followCount' segmentos (NO esperar)
    const genKey = `${documentoId}:${voiceId}`;
    if (activeGenerations.has(genKey)) {
      console.log(`[QuickStart] ⏭️ Generación background ya activa para ${genKey}`);
    } else {
      activeGenerations.add(genKey);
      (async () => {
      try {
        const nextSegsResult = await pool.query(
          `SELECT s.id, s.orden, s.texto 
           FROM tbl_segmentos s
           LEFT JOIN tbl_audios a ON a.segmento_id = s.id AND a.documento_id = s.documento_id AND a.voz_id = $2
           WHERE s.documento_id = $1 AND s.orden > $3 AND a.id IS NULL
           ORDER BY s.orden ASC
           LIMIT $4`,
          [documentoId, voiceId, firstSegment.orden, followCount]
        );

        if (nextSegsResult.rows.length > 0) {
          console.log(`   🔄 Generando ${nextSegsResult.rows.length} segmentos adicionales en background (requested ${followCount})...`);
          
          const voiceResult = await pool.query(
            `SELECT codigo_voz, configuracion FROM tbl_voces WHERE id = $1`,
            [voiceId]
          );
          const voice = voiceResult.rows[0];

          for (const seg of nextSegsResult.rows) {
            try {
              const audioBuffer = await generateAudio(seg.texto, voice.codigo_voz, voice.configuracion || {});
              const safeVoice = (voice.codigo_voz || 'voz').replace(/[^a-zA-Z0-9_-]/g, '_');
              const fileName = `libro_${libroId}/voz_${safeVoice}/segmento_${seg.orden}.mp3`;
              
              await supabase.storage.from('audios_tts').upload(fileName, audioBuffer, {
                contentType: 'audio/mpeg',
                upsert: true
              });

              const { data: urlData } = supabase.storage.from('audios_tts').getPublicUrl(fileName);
              const duracion = safeDurationMs(seg.texto, (voice.configuracion || {}).rate);

              await pool.query(
                `INSERT INTO tbl_audios (documento_id, segmento_id, voz_id, audio_url, duracion_ms, last_access_at, access_count)
                 VALUES ($1, $2, $3, $4, $5, NOW(), 1)
                 ON CONFLICT (documento_id, segmento_id, voz_id) 
                 DO UPDATE SET audio_url = EXCLUDED.audio_url, duracion_ms = EXCLUDED.duracion_ms`,
                [documentoId, seg.id, voiceId, urlData.publicUrl, duracion]
              );

              console.log(`   ✅ Segmento ${seg.orden} generado en background`);
            } catch (err) {
              console.error(`   ⚠️  Error en segmento ${seg.orden}:`, err.message);
            }
          }
        }
      } catch (err) {
        console.error('   ⚠️  Error en generación background:', err.message);
      } finally {
        activeGenerations.delete(genKey);
      }
    })(); // Fire and forget
    }

    // 6. Responder inmediatamente con el primer audio
    res.json({
      success: true,
      documento_id: documentoId, // Agregar documento_id para saveProgress
      first_audio_url: firstAudioUrl,
      segment_orden: firstSegment.orden,
      next_count: followCount,
      message: `Primer audio listo. Generando siguientes ${followCount} en background.`
    });

  } catch (error) {
    console.error('[QuickStart] Error:', error);
    res.status(500).json({ error: 'Error en quick-start', detail: error.message });
  }
};

export {
  getVoices,
  getPlaylist,
  getSegmentAudio,
  saveProgress,
  getProgress,
  getBookAudios,
  quickStartBook,
};
