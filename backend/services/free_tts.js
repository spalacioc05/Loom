/**
 * Free TTS provider using google-tts-api (Google Translate TTS unofficial).
 * 
 * NOTA IMPORTANTE: Google TTS no soporta selección real de voces.
 * Todas las variantes de español mapean a 'es' en el API.
 * Los códigos de voz en la BD (es-MX-Female, es-ES-Male, etc.) son 
 * para la UI del usuario, pero el audio será el mismo 'es'.
 * 
 * En el futuro, se podría:
 * - Usar otro proveedor gratuito con más opciones (ElevenLabs, PlayHT, etc.)
 * - Implementar procesamiento de voz local (piper-tts, coqui-ai)
 * - Agregar efectos de audio para simular diferentes voces (pitch, speed)
 */

import googleTTS from 'google-tts-api';

/**
 * Mapea el código de voz a un idioma soportado por Google TTS.
 * Google TTS soporta: es, en, fr, de, it, pt, ru, ja, ko, zh-CN, etc.
 * Pero NO distingue entre acentos (es-MX, es-ES, es-AR son todos 'es').
 */
function mapLang(voiceCode) {
  if (!voiceCode) return 'es';
  const low = String(voiceCode).toLowerCase();
  
  // Todas las variantes de español mapean a 'es'
  if (low.startsWith('es-') || low === 'es') return 'es';
  
  // Inglés
  if (low.startsWith('en-') || low === 'en') return 'en';
  
  // Francés
  if (low.startsWith('fr-') || low === 'fr') return 'fr';
  
  // Alemán
  if (low.startsWith('de-') || low === 'de') return 'de';
  
  // Italiano
  if (low.startsWith('it-') || low === 'it') return 'it';
  
  // Portugués
  if (low.startsWith('pt-') || low === 'pt') return 'pt';
  
  // Default: español
  return 'es';
}

export async function generateAudio(text, voiceCode, options = {}) {
  const lang = mapLang(voiceCode);
  
  // Determinar si es voz lenta (slow) basado en el código de voz
  // Usamos slow=true para voces "Female" para diferenciarlas
  const isFemale = voiceCode && voiceCode.toLowerCase().includes('female');
  const slow = isFemale; // Las voces femeninas serán más lentas/claras
  
  console.log(`[Free TTS] Generando audio con idioma: ${lang}, voz: ${voiceCode}, slow: ${slow}`);
  console.log(`[Free TTS] Texto (${text.length} caracteres): "${text.substring(0, 80)}..."`);
  
  // getAllAudioUrls divide el texto en partes válidas para el endpoint
  const parts = googleTTS.getAllAudioUrls(text, {
    lang,
    slow,
    host: 'https://translate.google.com',
  });

  console.log(`[Free TTS] Dividido en ${parts.length} partes (velocidad: ${slow ? 'lenta' : 'normal'})`);

  const buffers = [];
  for (let i = 0; i < parts.length; i++) {
    const p = parts[i];
    try {
      const res = await fetch(p.url);
      if (!res.ok) {
        const msg = await res.text().catch(() => res.statusText);
        throw new Error(`google-tts fetch error ${res.status}: ${msg}`);
      }
      const ab = await res.arrayBuffer();
      buffers.push(Buffer.from(ab));
      console.log(`[Free TTS] Parte ${i + 1}/${parts.length} descargada (${ab.byteLength} bytes)`);
    } catch (err) {
      console.error(`[Free TTS] Error en parte ${i + 1}:`, err.message);
      throw err;
    }
  }
  
  // Concatenar MP3s: suficiente para streaming simple
  const finalBuffer = Buffer.concat(buffers);
  console.log(`[Free TTS] ✅ Audio generado: ${finalBuffer.length} bytes`);
  return finalBuffer;
}

export function estimateDuration(text) {
  // Aproximación similar a azure_tts
  const words = (text || '').split(/\s+/).filter(Boolean).length;
  const baseWpm = 150;
  const minutes = words / baseWpm;
  return Math.round(minutes * 60 * 1000);
}
