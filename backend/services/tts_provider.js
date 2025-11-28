/**
 * TTS Provider Selector
 * 
 * Selecciona automáticamente entre Google TTS, Azure TTS y Free TTS según disponibilidad
 * de credenciales o configuración explícita.
 */

import { generateAudio as azureGen, estimateDuration as azureEst } from './azure_tts.js';
import { generateAudio as freeGen, estimateDuration as freeEst } from './free_tts.js';
import { generateAudio as googleGen, estimateDuration as googleEst } from './google_tts.js';

function hasAzureCreds() {
  return !!(process.env.AZURE_SPEECH_KEY && process.env.AZURE_SPEECH_REGION);
}

function hasGoogleCreds() {
  return !!(process.env.GOOGLE_APPLICATION_CREDENTIALS);
}

const provider = (() => {
  const forced = (process.env.TTS_PROVIDER || '').toLowerCase();
  if (forced === 'google') {
    console.log('[TTS Provider] Usando Google TTS (forzado por TTS_PROVIDER)');
    return 'google';
  }
  if (forced === 'azure') {
    console.log('[TTS Provider] Usando Azure TTS (forzado por TTS_PROVIDER)');
    return 'azure';
  }
  if (forced === 'free') {
    console.log('[TTS Provider] Usando Free TTS (forzado por TTS_PROVIDER)');
    return 'free';
  }
  // Auto-selección: Google > Azure > Free
  if (hasGoogleCreds()) {
    console.log('[TTS Provider] Usando Google TTS (auto-detectado)');
    return 'google';
  }
  if (hasAzureCreds()) {
    console.log('[TTS Provider] Usando Azure TTS (auto-detectado)');
    return 'azure';
  }
  console.log('[TTS Provider] Usando Free TTS (auto-detectado, sin credenciales)');
  return 'free';
})();

export async function generateAudio(text, voiceCode, options = {}) {
  if (process.env.MOCK_TTS === 'true') {
    // Reusar mock de azure_tts para mantener consistencia
    console.log('[TTS Provider] Usando MOCK TTS');
    return azureGen(text, voiceCode, options);
  }
  if (provider === 'google') {
    return googleGen(text, voiceCode, options);
  }
  if (provider === 'azure') {
    return azureGen(text, voiceCode, options);
  }
  return freeGen(text, voiceCode, options);
}

export function estimateDuration(text, rate) {
  if (provider === 'google') {
    return googleEst(text, rate);
  }
  if (provider === 'azure') {
    return azureEst(text, rate);
  }
  return freeEst(text);
}

export function currentTtsProvider() {
  return provider;
}
