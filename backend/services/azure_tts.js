/**
 * Servicio de Text-to-Speech usando Azure Cognitive Services
 * 
 * Genera audio natural a partir de texto usando voces neuronales.
 * Soporta SSML para control fino de entonación, pausas y velocidad.
 */

import sdk from 'microsoft-cognitiveservices-speech-sdk';

/**
 * Genera audio MP3 a partir de texto usando Azure Neural TTS
 * 
 * @param {string} text - Texto a sintetizar
 * @param {string} voiceCode - Código de voz (ej: "es-MX-DaliaNeural")
 * @param {object} options - Opciones: rate (0.5-2.0), pitch (-50% a +50%), style
 * @param {number} retries - Número de reintentos en caso de error
 * @returns {Promise<Buffer>} Buffer con audio MP3
 */
export async function generateAudio(text, voiceCode, options = {}, retries = 3) {
  // Modo mock para pruebas locales o cuando Azure está sin cuota
  if (process.env.MOCK_TTS === 'true') {
    // Generar un pequeño MP3 sintético reprocesando texto con marcadores simples sin depender de Azure
    // Para evitar depender de binarios externos, retornamos un MP3 silencioso de ~0.5s.
    // Si se necesita más duración, concatenar bytes repetidos.
    const silentMp3Base64 =
      'SUQzAwAAAAAAQlRFMgAAAA8AAAADAAACAAADAAACAAACAAACAAACAAACAAACAAACAAACAAACAAAAAAA' +
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' +
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    let buf = Buffer.from(silentMp3Base64, 'base64');
    // Extender (duplicar) para simular duración según tamaño del texto (aprox 1s por 1500 chars)
    const repeats = Math.min(4, Math.max(1, Math.ceil(text.length / 1500))); // hasta ~2s
    buf = Buffer.concat(Array.from({ length: repeats }, () => buf));
    return buf;
  }

  const speechKey = process.env.AZURE_SPEECH_KEY;
  const speechRegion = process.env.AZURE_SPEECH_REGION;

  if (!speechKey || !speechRegion) {
    throw new Error('Azure Speech credentials not configured. Set AZURE_SPEECH_KEY and AZURE_SPEECH_REGION.');
  }

  // Convertir rate de número (0.5-2.0) a porcentaje para Azure
  // rate de Flutter: 0.5 = -50%, 1.0 = 0%, 2.0 = +100%
  let rateValue;
  if (typeof options.rate === 'number') {
    const percentage = Math.round((options.rate - 1.0) * 100);
    rateValue = `${percentage >= 0 ? '+' : ''}${percentage}%`;
  } else {
    rateValue = options.rate || '0%';
  }

  const pitch = options.pitch || '0%';
  
  // SSML mejorado para fluidez
  const ssml = `
    <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="es-MX">
      <voice name="${voiceCode}">
        <prosody rate="${rateValue}" pitch="${pitch}">
          ${escapeXml(text)}
        </prosody>
      </voice>
    </speak>
  `.trim();

  console.log(`[Azure TTS] Generando audio con voz: ${voiceCode}, rate: ${rateValue}, pitch: ${pitch}`);
  console.log(`[Azure TTS] Texto (${text.length} caracteres): "${text.substring(0, 80)}..."`);

  // Función interna con reintentos
  async function tryGenerate(attempt = 1) {
    // Configurar Azure Speech SDK
    const speechConfig = sdk.SpeechConfig.fromSubscription(speechKey, speechRegion);
    speechConfig.speechSynthesisOutputFormat = sdk.SpeechSynthesisOutputFormat.Audio24Khz160KBitRateMonoMp3;

    const synthesizer = new sdk.SpeechSynthesizer(speechConfig);

    return new Promise((resolve, reject) => {
      synthesizer.speakSsmlAsync(
        ssml,
        result => {
          synthesizer.close();
          
          if (result.reason === sdk.ResultReason.SynthesizingAudioCompleted) {
            const audioBuffer = Buffer.from(result.audioData);
            console.log(`[Azure TTS] ✅ Audio generado: ${audioBuffer.length} bytes`);
            resolve(audioBuffer);
          } else if (result.reason === sdk.ResultReason.Canceled) {
            const cancellation = sdk.CancellationDetails.fromResult(result);
            console.error(`[Azure TTS] ❌ Error (intento ${attempt}/${retries}): ${cancellation.reason}`);
            if (cancellation.reason === sdk.CancellationReason.Error) {
              console.error(`[Azure TTS] Error details: ${cancellation.errorDetails}`);
            }
            
            // Reintentar si quedan intentos
            if (attempt < retries) {
              const delay = attempt * 2000; // 2s, 4s, 6s...
              console.log(`[Azure TTS] ⏳ Reintentando en ${delay}ms...`);
              setTimeout(async () => {
                try {
                  const result = await tryGenerate(attempt + 1);
                  resolve(result);
                } catch (err) {
                  reject(err);
                }
              }, delay);
            } else {
              reject(new Error(`Speech synthesis canceled after ${retries} attempts: ${cancellation.reason}`));
            }
          } else {
            reject(new Error(`Unexpected result reason: ${result.reason}`));
          }
        },
        error => {
          synthesizer.close();
          console.error(`[Azure TTS] ❌ Synthesis error (intento ${attempt}/${retries}):`, error);
          
          // Reintentar si quedan intentos
          if (attempt < retries) {
            const delay = attempt * 2000;
            console.log(`[Azure TTS] ⏳ Reintentando en ${delay}ms...`);
            setTimeout(async () => {
              try {
                const result = await tryGenerate(attempt + 1);
                resolve(result);
              } catch (err) {
                reject(err);
              }
            }, delay);
          } else {
            reject(error);
          }
        }
      );
    });
  }

  // Fallback por REST (HTTP) para entornos donde WebSocket está bloqueado
  async function tryGenerateRest() {
    const endpoint = `https://${speechRegion}.tts.speech.microsoft.com/cognitiveservices/v1`;
    const headers = {
      'Content-Type': 'application/ssml+xml',
      'Ocp-Apim-Subscription-Key': speechKey,
      'X-Microsoft-OutputFormat': 'audio-24khz-160kbitrate-mono-mp3',
      'User-Agent': 'LoomApp/1.0',
    };
    const res = await fetch(endpoint, {
      method: 'POST',
      headers,
      body: ssml,
    });
    if (!res.ok) {
      const msg = await res.text().catch(() => res.statusText);
      throw new Error(`Azure REST TTS error ${res.status}: ${msg}`);
    }
    const ab = await res.arrayBuffer();
    const buf = Buffer.from(ab);
    console.log(`[Azure TTS REST] ✅ Audio generado: ${buf.length} bytes`);
    return buf;
  }

  try {
    return await tryGenerate();
  } catch (wsErr) {
    console.warn('[Azure TTS] WebSocket synthesis failed, trying REST fallback:', wsErr?.message || wsErr);
    // REST sin reintentos complejos; si falla, elevar error
    return await tryGenerateRest();
  }
}

/**
 * Estima la duración del audio en milisegundos
 * Aproximación: ~150 palabras por minuto para español neutro
 */
export function estimateDuration(text, rate = 'medium') {
  const words = text.split(/\s+/).length;
  const baseWpm = 150; // palabras por minuto
  
  const rateMultipliers = {
    'x-slow': 0.5,
    'slow': 0.75,
    'medium': 1.0,
    'fast': 1.25,
    'x-fast': 1.5,
  };
  
  const multiplier = rateMultipliers[rate] || 1.0;
  const adjustedWpm = baseWpm * multiplier;
  const durationMinutes = words / adjustedWpm;
  
  return Math.round(durationMinutes * 60 * 1000); // convertir a ms
}

/**
 * Escapa caracteres especiales XML/SSML
 */
function escapeXml(unsafe) {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * Lista de voces neuronales disponibles para español
 * Actualizar según necesidades del proyecto
 */
export const AVAILABLE_VOICES = [
  { code: 'es-MX-DaliaNeural', lang: 'es-MX', gender: 'Female', description: 'México - Dalia (Mujer)' },
  { code: 'es-MX-JorgeNeural', lang: 'es-MX', gender: 'Male', description: 'México - Jorge (Hombre)' },
  { code: 'es-CO-SalomeNeural', lang: 'es-CO', gender: 'Female', description: 'Colombia - Salomé (Mujer)' },
  { code: 'es-CO-GonzaloNeural', lang: 'es-CO', gender: 'Male', description: 'Colombia - Gonzalo (Hombre)' },
  { code: 'es-ES-ElviraNeural', lang: 'es-ES', gender: 'Female', description: 'España - Elvira (Mujer)' },
  { code: 'es-ES-AlvaroNeural', lang: 'es-ES', gender: 'Male', description: 'España - Álvaro (Hombre)' },
  { code: 'es-AR-ElenaNeural', lang: 'es-AR', gender: 'Female', description: 'Argentina - Elena (Mujer)' },
  { code: 'es-AR-TomasNeural', lang: 'es-AR', gender: 'Male', description: 'Argentina - Tomás (Hombre)' },
];
