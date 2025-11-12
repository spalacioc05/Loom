/**
 * TTS Provider Selector
 * 
 * Selecciona automáticamente entre Azure TTS y Free TTS según disponibilidad
 * de credenciales o configuración explícita.
 */

import { generateAudio as azureGen, estimateDuration as azureEst } from './azure_tts.js';
import { generateAudio as freeGen, estimateDuration as freeEst } from './free_tts.js';

function hasAzureCreds() {
  return !!(process.env.AZURE_SPEECH_KEY && process.env.AZURE_SPEECH_REGION);
}

const provider = (() => {
  const forced = (process.env.TTS_PROVIDER || '').toLowerCase();
  if (forced === 'azure') {
    console.log('[TTS Provider] Usando Azure TTS (forzado por TTS_PROVIDER)');
    return 'azure';
  }
  if (forced === 'free') {
    console.log('[TTS Provider] Usando Free TTS (forzado por TTS_PROVIDER)');
    return 'free';
  }
  // Auto-selección: si hay credenciales de Azure, usarlas; si no, free
  if (hasAzureCreds()) {
    console.log('[TTS Provider] Usando Azure TTS (auto-detectado)');
    return 'azure';
  }
  console.log('[TTS Provider] Usando Free TTS (auto-detectado, sin credenciales Azure)');
  return 'free';
})();

export async function generateAudio(text, voiceCode, options = {}) {
  if (process.env.MOCK_TTS === 'true') {
    // Reusar mock de azure_tts para mantener consistencia
    console.log('[TTS Provider] Usando MOCK TTS');
    return azureGen(text, voiceCode, options);
  }
  return provider === 'azure'
    ? azureGen(text, voiceCode, options)
    : freeGen(text, voiceCode, options);
}

export function estimateDuration(text, rate) {
  return provider === 'azure'
    ? azureEst(text, rate)
    : freeEst(text);
}

export function currentTtsProvider() {
  return provider;
}
