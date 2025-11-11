/**
 * Servicio de cola TTS con BullMQ
 * 
 * Permite encolar trabajos de generación de audio desde la API.
 */

import { Queue } from 'bullmq';

const redisConnection = {
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379', 10),
};

let ttsQueue = null;
let queueDisabled = process.env.QUEUE_ENABLED === 'false';

function ensureQueue() {
  if (queueDisabled) return null;
  if (ttsQueue) return ttsQueue;
  try {
    ttsQueue = new Queue('tts-queue', {
      connection: redisConnection,
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 2000 },
        removeOnComplete: true,
        removeOnFail: false,
      },
    });
    console.log(`[TTS Queue] 📡 Cola TTS conectada a Redis: ${redisConnection.host}:${redisConnection.port}`);
    // Evitar que errores de conexión tumben el proceso
    ttsQueue?.on('error', (err) => {
      console.warn('[TTS Queue] ⚠️  Error de Redis, deshabilitando cola temporalmente:', err?.message || err);
      queueDisabled = true;
    });
  } catch (err) {
    console.warn('[TTS Queue] ⚠️  No se pudo inicializar la cola. Continuando sin Redis. Motivo:', err?.message || err);
    queueDisabled = true;
    ttsQueue = null;
  }
  return ttsQueue;
}

/**
 * Encola generación de audio para un segmento
 * 
 * @param {string} documentId - UUID del documento
 * @param {string} segmentId - UUID del segmento
 * @param {string} voiceId - UUID de la voz
 * @param {object} options - Opciones adicionales (prioridad, delay, etc.)
 * @returns {Promise<Job>}
 */
export async function enqueueSegment(documentId, segmentId, voiceId, options = {}) {
  const q = ensureQueue();
  if (!q) {
    console.log('[TTS Queue] ⏭️  Redis no disponible, omitiendo enqueue de un segmento.');
    return null;
  }
  const jobName = `${documentId}:${segmentId}:${voiceId}`;
  const job = await q.add('generate-audio', { documentId, segmentId, voiceId }, {
    jobId: jobName,
    priority: options.priority || 10,
    delay: options.delay || 0,
    ...options,
  });
  console.log(`[TTS Queue] ✉️ Encolado job: ${job.id}`);
  return job;
}

/**
 * Encola batch de segmentos (para precarga n+1, n+2, etc.)
 */
export async function enqueueBatch(documentId, segmentIds, voiceId, options = {}) {
  const q = ensureQueue();
  if (!q) {
    console.log('[TTS Queue] ⏭️  Redis no disponible, omitiendo enqueue batch.');
    return [];
  }
  const jobs = segmentIds.map((segmentId, index) => ({
    name: 'generate-audio',
    data: { documentId, segmentId, voiceId },
    opts: {
      jobId: `${documentId}:${segmentId}:${voiceId}`,
      priority: (options.basePriority || 10) + index,
      ...options,
    },
  }));
  const addedJobs = await q.addBulk(jobs);
  console.log(`[TTS Queue] 📦 Encolados ${addedJobs.length} jobs en batch`);
  return addedJobs;
}

/**
 * Obtiene estado de un job
 */
export async function getJobStatus(documentId, segmentId, voiceId) {
  const q = ensureQueue();
  if (!q) return null;
  const jobId = `${documentId}:${segmentId}:${voiceId}`;
  const job = await q.getJob(jobId);
  if (!job) return null;
  const state = await job.getState();
  return { id: job.id, state, progress: job.progress, returnvalue: job.returnvalue, failedReason: job.failedReason };
}

/**
 * Obtiene métricas de la cola
 */
export async function getQueueMetrics() {
  const q = ensureQueue();
  if (!q) return { waiting: 0, active: 0, completed: 0, failed: 0 };
  const [waiting, active, completed, failed] = await Promise.all([
    q.getWaitingCount(),
    q.getActiveCount(),
    q.getCompletedCount(),
    q.getFailedCount(),
  ]);
  return { waiting, active, completed, failed };
}

