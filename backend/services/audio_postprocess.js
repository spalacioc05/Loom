import ffmpeg from 'fluent-ffmpeg';
import ffmpegPath from 'ffmpeg-static';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Proper __dirname in ESM (Windows-safe)
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Ensure ffmpeg binary path is set for fluent-ffmpeg
if (ffmpegPath) {
  ffmpeg.setFfmpegPath(ffmpegPath);
}

/**
 * Apply lightweight pitch/speed transform to an input audio file using atempo/asetrate filters.
 * Inputs:
 * - inputPath: absolute path to source mp3 file
 * - outputPath: absolute path to write transformed mp3 file
 * - options: { pitchSemitones?: number, speed?: number }
 *   pitchSemitones: positive raises pitch, negative lowers pitch (small values like +/-1 recommended)
 *   speed: playback speed multiplier (e.g., 0.95, 1.05). If omitted, defaults to 1.0
 * Returns: Promise<string> resolves to outputPath when done.
 */
function processAudioFile(inputPath, outputPath, options = {}) {
  const { pitchSemitones = 0, speed = 1.0 } = options;

  // Build filter chain. We'll use asetrate to change pitch and atempo to adjust tempo back to near-normal.
  // Pitch factor from semitones: factor = 2^(semitones/12)
  const pitchFactor = Math.pow(2, pitchSemitones / 12);

  // We apply asetrate to shift pitch, then atempo to correct duration combined with desired speed.
  // Effective tempo = (1 / pitchFactor) * speed
  const effectiveTempo = Math.max(0.5, Math.min(2.0, (1 / pitchFactor) * speed));

  // Clamp effectiveTempo within ffmpeg atempo limits [0.5, 2.0]
  const targetSr = 44100;
  const filter = `asetrate=${targetSr}*${pitchFactor},aresample=${targetSr},atempo=${effectiveTempo}`;

  return new Promise((resolve, reject) => {
    ffmpeg(inputPath)
      .audioFilter(filter)
      .audioCodec('libmp3lame')
      .outputOptions(['-q:a 4'])
      .on('error', (err) => {
        reject(err);
      })
      .on('end', () => {
        resolve(outputPath);
      })
      .save(outputPath);
  });
}

/**
 * Convenience method: process a buffer and return processed buffer.
 * Writes to temp files under backend/tmp and cleans up.
 */
async function processAudioBuffer(buf, { pitchSemitones = 0, speed = 1.0 } = {}) {
  const tmpDir = path.resolve(__dirname, '..', 'tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  const inPath = path.join(tmpDir, `in_${Date.now()}_${Math.random().toString(36).slice(2)}.mp3`);
  const outPath = path.join(tmpDir, `out_${Date.now()}_${Math.random().toString(36).slice(2)}.mp3`);
  fs.writeFileSync(inPath, buf);

  try {
    await processAudioFile(inPath, outPath, { pitchSemitones, speed });
    const outBuf = fs.readFileSync(outPath);
    return outBuf;
  } finally {
    // Cleanup best-effort
    try { fs.unlinkSync(inPath); } catch {}
    try { fs.unlinkSync(outPath); } catch {}
  }
}

export { processAudioFile, processAudioBuffer };
