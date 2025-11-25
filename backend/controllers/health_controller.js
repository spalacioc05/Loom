import sql from '../db/client.js';
import pkg from 'pg';
const { Pool } = pkg;

// Usamos pg Pool solo para comprobar compatibilidad con el otro cliente si se desea.
// Si DATABASE_URL no existe, devolvemos estado degradado.
const connectionString = process.env.DATABASE_URL;
let pool = null;
if (connectionString) {
  try {
    pool = new Pool({ connectionString });
  } catch (e) {
    console.warn('[Health] No se pudo inicializar Pool pg:', e.message);
  }
}

export async function healthCheck(req, res) {
  const report = { ok: true, timestamp: new Date().toISOString(), checks: {} };
  // Check Postgres (via postgres library)
  try {
    const time = await sql`SELECT NOW()`;
    report.checks.postgres_primary = { ok: true, now: time[0].now };
  } catch (e) {
    report.ok = false;
    report.checks.postgres_primary = { ok: false, error: e.message };
  }
  // Check voices table
  try {
    const voices = await sql`SELECT count(*)::int AS total FROM tbl_voces`;
    report.checks.voices = { ok: true, total: voices[0].total };
  } catch (e) {
    report.ok = false;
    report.checks.voices = { ok: false, error: e.message };
  }
  // Optional pg Pool test
  if (pool) {
    try {
      const r = await pool.query('SELECT 1 AS one');
      report.checks.pg_pool = { ok: true, one: r.rows[0].one };
    } catch (e) {
      report.checks.pg_pool = { ok: false, error: e.message };
    }
  }
  // Azure Speech env vars
  report.checks.azure_speech = {
    has_key: !!process.env.AZURE_SPEECH_KEY,
    has_region: !!process.env.AZURE_SPEECH_REGION,
  };
  report.checks.queue_enabled = process.env.QUEUE_ENABLED !== 'false';
  res.status(report.ok ? 200 : 500).json(report);
}
