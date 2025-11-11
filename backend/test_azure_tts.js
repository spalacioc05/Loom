/**
 * Test de Azure Speech Services
 * 
 * Prueba que las credenciales funcionan generando un audio de prueba.
 * 
 * Uso: node test_azure_tts.js
 */

import 'dotenv/config';
import { generateAudio } from './services/azure_tts.js';
import fs from 'fs';

async function testAzureTTS() {
  console.log('🧪 Probando Azure Speech Services...\n');

  // Verificar variables de entorno
  if (!process.env.AZURE_SPEECH_KEY) {
    console.error('❌ Error: AZURE_SPEECH_KEY no está configurada en .env');
    process.exit(1);
  }

  if (!process.env.AZURE_SPEECH_REGION) {
    console.error('❌ Error: AZURE_SPEECH_REGION no está configurada en .env');
    process.exit(1);
  }

  console.log('✅ Variables de entorno configuradas:');
  console.log(`   Region: ${process.env.AZURE_SPEECH_REGION}`);
  console.log(`   Key: ${process.env.AZURE_SPEECH_KEY.substring(0, 8)}...`);
  console.log('');

  // Texto de prueba
  const textoCorto = 'Hola, este es un test de síntesis de voz con Azure Speech Services.';
  const voiceCode = 'es-MX-DaliaNeural'; // Voz mexicana femenina

  try {
    console.log('🎙️ Generando audio de prueba...');
    console.log(`   Voz: ${voiceCode}`);
    console.log(`   Texto: "${textoCorto}"`);
    console.log('');

    const audioBuffer = await generateAudio(textoCorto, voiceCode, {
      rate: 'medium',
      pitch: '+0st'
    });

    // Guardar en archivo temporal
    const outputFile = 'test_output.mp3';
    fs.writeFileSync(outputFile, audioBuffer);

    console.log('✅ ¡Audio generado exitosamente!');
    console.log(`   Archivo: ${outputFile}`);
    console.log(`   Tamaño: ${(audioBuffer.length / 1024).toFixed(2)} KB`);
    console.log('');
    console.log('🎵 Abre "test_output.mp3" para escuchar el resultado');
    console.log('');
    console.log('✨ Azure Speech Services está funcionando correctamente!');

  } catch (error) {
    console.error('❌ Error generando audio:', error.message);
    console.error('');
    console.error('Posibles causas:');
    console.error('  - AZURE_SPEECH_KEY incorrecta');
    console.error('  - AZURE_SPEECH_REGION incorrecta');
    console.error('  - Sin conexión a internet');
    console.error('  - Cuota excedida (improbable en free tier)');
    console.error('');
    console.error('Error completo:', error);
    process.exit(1);
  }
}

testAzureTTS()
  .then(() => {
    console.log('Test completado');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Test falló:', error);
    process.exit(1);
  });
