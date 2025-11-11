import { generateAudio } from './services/azure_tts.js';
import fs from 'fs';
import dotenv from 'dotenv';

// Cargar variables de entorno
dotenv.config();

async function testAzureTTS() {
  try {
    console.log('🎤 Probando Azure Text-to-Speech...');
    console.log('AZURE_SPEECH_KEY:', process.env.AZURE_SPEECH_KEY ? '✅ Configurada' : '❌ No encontrada');
    console.log('AZURE_SPEECH_REGION:', process.env.AZURE_SPEECH_REGION || '❌ No encontrada');
    
    const texto = 'Hola, esta es una prueba de síntesis de voz con Azure.';
    const voz = 'es-MX-DaliaNeural';
    
    console.log(`Texto: "${texto}"`);
    console.log(`Voz: ${voz}`);
    
    const audioBuffer = await generateAudio(texto, voz);
    
    console.log(`✅ Audio generado: ${audioBuffer.length} bytes`);
    
    // Guardar archivo de prueba
    fs.writeFileSync('test_audio.mp3', audioBuffer);
    console.log('✅ Audio guardado en test_audio.mp3');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error.stack);
  }
}

testAzureTTS();
