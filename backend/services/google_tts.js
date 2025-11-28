import textToSpeech from '@google-cloud/text-to-speech';

// Cliente de Google Cloud TTS (se inicializa automáticamente con GOOGLE_APPLICATION_CREDENTIALS)
let client = null;

/**
 * Inicializa el cliente de Google Cloud TTS si las credenciales están disponibles
 */
function initializeClient() {
  if (client) return client;
  
  try {
    // El cliente se autentica automáticamente usando GOOGLE_APPLICATION_CREDENTIALS
    client = new textToSpeech.TextToSpeechClient();
    console.log('✅ Google Cloud TTS client inicializado');
    return client;
  } catch (error) {
    console.error('❌ Error inicializando Google Cloud TTS:', error.message);
    throw error;
  }
}

/**
 * Genera audio usando Google Cloud Text-to-Speech
 * @param {string} text - Texto a convertir en audio
 * @param {string} voiceCode - Código de voz (ej: es-US-Neural2-A)
 * @param {object} config - Configuración adicional (rate, pitch, volume)
 * @returns {Promise<Buffer>} - Audio en formato MP3
 */
export async function generateAudio(text, voiceCode, config = {}) {
  const ttsClient = initializeClient();
  
  // Extraer idioma del código de voz (ej: es-US-Neural2-A -> es-US)
  const langMatch = voiceCode.match(/^([a-z]{2}-[A-Z]{2})/);
  const languageCode = langMatch ? langMatch[1] : 'es-US';
  
  // Extraer género del settings_json o inferir del código
  let ssmlGender = 'NEUTRAL';
  if (config.ssmlGender) {
    ssmlGender = config.ssmlGender.toUpperCase();
  } else {
    // Inferir género por convención: A/C/E ~ FEMALE, B/D/F ~ MALE
    const lastChar = voiceCode.slice(-1);
    if (['A', 'C', 'E', 'G', 'I'].includes(lastChar)) {
      ssmlGender = 'FEMALE';
    } else if (['B', 'D', 'F', 'H', 'J'].includes(lastChar)) {
      ssmlGender = 'MALE';
    }
  }
  
  // Normalizar rate y pitch para Google Cloud
  // Google acepta rate entre 0.25 y 4.0 (1.0 = normal)
  // Azure usa porcentaje: 100% = normal, Google usa multiplicador: 1.0 = normal
  let speakingRate = 1.0;
  if (config.rate) {
    const rateStr = config.rate.toString();
    if (rateStr.includes('%')) {
      // Convertir porcentaje a multiplicador (ej: 120% -> 1.2)
      speakingRate = parseFloat(rateStr.replace('%', '')) / 100;
    } else {
      speakingRate = parseFloat(rateStr);
    }
  }
  
  // Google acepta pitch entre -20.0 y 20.0 (0 = normal)
  let pitch = 0.0;
  if (config.pitch) {
    const pitchStr = config.pitch.toString();
    if (pitchStr.includes('%')) {
      // Convertir porcentaje a semitones (ej: 120% -> +3.9, 80% -> -4.5)
      const percentage = parseFloat(pitchStr.replace('%', ''));
      pitch = (percentage - 100) / 5; // Aproximación: cada 5% ≈ 1 semitono
    } else if (pitchStr.includes('Hz')) {
      // Ignorar valores absolutos en Hz (usar default)
      pitch = 0.0;
    } else {
      pitch = parseFloat(pitchStr);
    }
  }
  
  // Google acepta volumeGainDb entre -96.0 y 16.0 (0 = sin cambio)
  let volumeGainDb = 0.0;
  if (config.volume) {
    const volStr = config.volume.toString();
    if (volStr.includes('%')) {
      // Convertir porcentaje a dB (ej: 100% = 0dB, 200% = +6dB, 50% = -6dB)
      const percentage = parseFloat(volStr.replace('%', ''));
      volumeGainDb = 20 * Math.log10(percentage / 100);
    } else {
      volumeGainDb = parseFloat(volStr);
    }
  }
  
  const request = {
    input: { text },
    voice: {
      languageCode,
      name: voiceCode,
      ssmlGender,
    },
    audioConfig: {
      audioEncoding: 'MP3',
      speakingRate: Math.max(0.25, Math.min(4.0, speakingRate)),
      pitch: Math.max(-20.0, Math.min(20.0, pitch)),
      volumeGainDb: Math.max(-96.0, Math.min(16.0, volumeGainDb)),
    },
  };
  
  console.log(`[Google TTS] Generando audio: ${voiceCode}, rate=${speakingRate}, pitch=${pitch}`);
  
  try {
    const [response] = await ttsClient.synthesizeSpeech(request);
    return Buffer.from(response.audioContent, 'binary');
  } catch (error) {
    console.error('[Google TTS] Error:', error.message);
    throw new Error(`Google TTS falló: ${error.message}`);
  }
}

/**
 * Lista voces disponibles de Google Cloud TTS
 * @param {string} languageCode - Código de idioma opcional (ej: es-US, en-US)
 * @returns {Promise<Array>} - Lista de voces disponibles
 */
export async function listVoices(languageCode = null) {
  const ttsClient = initializeClient();
  
  const request = languageCode ? { languageCode } : {};
  
  try {
    const [response] = await ttsClient.listVoices(request);
    return response.voices || [];
  } catch (error) {
    console.error('[Google TTS] Error listando voces:', error.message);
    throw error;
  }
}

/**
 * Estima la duración del audio basado en el texto y la velocidad
 * @param {string} text - Texto del audio
 * @param {number|string} rate - Velocidad de habla
 * @returns {number} - Duración estimada en milisegundos
 */
export function estimateDuration(text, rate = 1.0) {
  // Velocidad promedio: ~150 palabras por minuto en español
  const wordsPerMinute = 150;
  const words = text.split(/\s+/).length;
  
  // Normalizar rate
  let normalizedRate = 1.0;
  if (rate) {
    const rateStr = rate.toString();
    if (rateStr.includes('%')) {
      normalizedRate = parseFloat(rateStr.replace('%', '')) / 100;
    } else {
      normalizedRate = parseFloat(rateStr);
    }
  }
  
  const minutes = words / (wordsPerMinute * normalizedRate);
  return Math.ceil(minutes * 60 * 1000); // convertir a milisegundos
}
