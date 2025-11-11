/**
 * Worker de limpieza de caché TTS (LRU + TTL)
 * 
 * Ejecuta tareas de mantenimiento:
 * - Elimina audios no accedidos en 60+ días
 * - Limpia documentos que exceden cuota de storage
 * - Actualiza métricas de uso
 * 
 * Ejecutar como cron: node workers/cache_cleanup.js
 */

import pkg from 'pg';
const { Pool } = pkg;
import { createClient } from '@supabase/supabase-js';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

// Configuración
const TTL_DAYS = parseInt(process.env.CACHE_TTL_DAYS || '60', 10);
const MAX_SIZE_PER_DOC_VOICE_MB = parseInt(process.env.MAX_CACHE_PER_DOC_VOICE_MB || '100', 10);

/**
 * Elimina audios no accedidos en X días (TTL)
 */
async function cleanupByTTL() {
  console.log(`\n[Cleanup TTL] 🧹 Buscando audios antiguos (>${TTL_DAYS} días)...`);

  try {
    // Obtener audios a eliminar
    const result = await pool.query(
      `SELECT id, audio_url, documento_id, voz_id, segmento_id
       FROM tbl_audios
       WHERE created_at < NOW() - INTERVAL '${TTL_DAYS} days'
         AND (last_access_at IS NULL OR last_access_at < NOW() - INTERVAL '${TTL_DAYS} days')
       LIMIT 1000`
    );

    if (result.rows.length === 0) {
      console.log('[Cleanup TTL] ✅ No hay audios antiguos para eliminar');
      return 0;
    }

    console.log(`[Cleanup TTL] 📋 Encontrados ${result.rows.length} audios a eliminar`);

    let deleted = 0;
    for (const audio of result.rows) {
      try {
        // Extraer path del audio desde URL
        const url = new URL(audio.audio_url);
        const pathMatch = url.pathname.match(/\/storage\/v1\/object\/public\/audios_tts\/(.+)$/);
        
        if (pathMatch) {
          const filePath = pathMatch[1];
          
          // Eliminar de Supabase Storage
          const { error } = await supabase.storage
            .from('audios_tts')
            .remove([filePath]);

          if (error) {
            console.error(`[Cleanup TTL] ⚠️ Error eliminando ${filePath}:`, error.message);
          } else {
            // Eliminar de BD
            await pool.query('DELETE FROM tbl_audios WHERE id = $1', [audio.id]);
            deleted++;
          }
        }
      } catch (err) {
        console.error(`[Cleanup TTL] ❌ Error procesando audio ${audio.id}:`, err.message);
      }
    }

    console.log(`[Cleanup TTL] ✅ Eliminados ${deleted}/${result.rows.length} audios\n`);
    return deleted;
  } catch (error) {
    console.error('[Cleanup TTL] ❌ Error:', error);
    throw error;
  }
}

/**
 * Limpia documentos que exceden cuota de storage (LRU)
 */
async function cleanupByQuota() {
  console.log(`\n[Cleanup LRU] 📊 Buscando documentos que exceden cuota (>${MAX_SIZE_PER_DOC_VOICE_MB} MB)...`);

  try {
    // Encontrar pares (documento, voz) que exceden cuota
    const result = await pool.query(
      `SELECT 
         documento_id,
         voz_id,
         COUNT(*) as total_audios,
         SUM(COALESCE(duracion_ms, 25000) / 1000.0 * 24 / 8 / 1024) as estimated_mb
       FROM tbl_audios
       GROUP BY documento_id, voz_id
       HAVING SUM(COALESCE(duracion_ms, 25000) / 1000.0 * 24 / 8 / 1024) > $1`,
      [MAX_SIZE_PER_DOC_VOICE_MB]
    );

    if (result.rows.length === 0) {
      console.log('[Cleanup LRU] ✅ No hay documentos que excedan cuota');
      return 0;
    }

    console.log(`[Cleanup LRU] 📋 Encontrados ${result.rows.length} pares (doc,voz) sobre cuota`);

    let totalDeleted = 0;
    for (const pair of result.rows) {
      try {
        // Obtener audios menos accedidos para este par (LRU)
        const toDelete = await pool.query(
          `SELECT id, audio_url
           FROM tbl_audios
           WHERE documento_id = $1 AND voz_id = $2
           ORDER BY COALESCE(last_access_at, created_at) ASC
           LIMIT 50`,
          [pair.documento_id, pair.voz_id]
        );

        for (const audio of toDelete.rows) {
          try {
            const url = new URL(audio.audio_url);
            const pathMatch = url.pathname.match(/\/storage\/v1\/object\/public\/audios_tts\/(.+)$/);
            
            if (pathMatch) {
              const filePath = pathMatch[1];
              await supabase.storage.from('audios_tts').remove([filePath]);
              await pool.query('DELETE FROM tbl_audios WHERE id = $1', [audio.id]);
              totalDeleted++;
            }
          } catch (err) {
            console.error(`[Cleanup LRU] ⚠️ Error eliminando audio:`, err.message);
          }
        }

        console.log(`[Cleanup LRU] ✅ Doc ${pair.documento_id.substring(0,8)}... / Voz ${pair.voz_id.substring(0,8)}...: eliminados ${toDelete.rows.length} audios menos usados`);
      } catch (err) {
        console.error('[Cleanup LRU] ❌ Error procesando par:', err);
      }
    }

    console.log(`[Cleanup LRU] ✅ Total eliminados: ${totalDeleted} audios\n`);
    return totalDeleted;
  } catch (error) {
    console.error('[Cleanup LRU] ❌ Error:', error);
    throw error;
  }
}

/**
 * Actualiza estadísticas de uso
 */
async function updateStats() {
  console.log('\n[Stats] 📈 Actualizando estadísticas...');

  try {
    const stats = await pool.query(`
      SELECT 
        COUNT(DISTINCT documento_id) as total_documentos,
        COUNT(DISTINCT voz_id) as total_voces_usadas,
        COUNT(*) as total_audios_cacheados,
        SUM(COALESCE(duracion_ms, 25000) / 1000.0 * 24 / 8 / 1024 / 1024) as total_gb_estimado,
        AVG(COALESCE(duracion_ms, 25000)) as avg_duracion_ms
      FROM tbl_audios
    `);

    const s = stats.rows[0];
    console.log(`[Stats] 📊 Resumen del caché:`);
    console.log(`  - Documentos con audio: ${s.total_documentos}`);
    console.log(`  - Voces usadas: ${s.total_voces_usadas}`);
    console.log(`  - Audios cacheados: ${s.total_audios_cacheados}`);
    console.log(`  - Storage estimado: ${parseFloat(s.total_gb_estimado).toFixed(2)} GB`);
    console.log(`  - Duración promedio: ${Math.round(s.avg_duracion_ms / 1000)}s\n`);
  } catch (error) {
    console.error('[Stats] ❌ Error:', error);
  }
}

/**
 * Ejecutar limpieza completa
 */
async function runCleanup() {
  console.log('🚀 [Cache Cleanup] Iniciando limpieza...');
  console.log(`⏰ [Cache Cleanup] ${new Date().toISOString()}\n`);

  try {
    await updateStats();
    
    const deletedTTL = await cleanupByTTL();
    const deletedLRU = await cleanupByQuota();

    console.log('\n✅ [Cache Cleanup] Limpieza completada');
    console.log(`   Total eliminados: ${deletedTTL + deletedLRU} audios\n`);

    await updateStats();
  } catch (error) {
    console.error('❌ [Cache Cleanup] Error fatal:', error);
    throw error;
  } finally {
    await pool.end();
  }
}

// Ejecutar
runCleanup()
  .then(() => {
    console.log('🎉 Proceso finalizado exitosamente');
    process.exit(0);
  })
  .catch((error) => {
    console.error('💥 Proceso falló:', error);
    process.exit(1);
  });
