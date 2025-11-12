import 'dotenv/config';

async function testQuickStart() {
  const libroId = 2; // Usar libro 2 que ya tiene segmentos
  const voiceId = 'cf8d5734-a987-47a5-8111-42aff5693b2f'; // es-Female-1 (primera voz de la lista)
  
  console.log('🚀 Probando quick-start...\n');
  console.log(`Libro: ${libroId}`);
  console.log(`Voz: ${voiceId}`);
  console.log('Esperando respuesta del servidor...\n');
  
  const startTime = Date.now();
  
  try {
    const response = await fetch('http://localhost:3000/tts/libro/2/quick-start', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ voiceId }),
    });
    
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(2);
    
    if (!response.ok) {
      const error = await response.text();
      throw new Error(`HTTP ${response.status}: ${error}`);
    }
    
    const data = await response.json();
    
    console.log('✅ Respuesta recibida!');
    console.log(`⏱️  Tiempo: ${elapsed} segundos\n`);
    console.log('📦 Datos:');
    console.log(JSON.stringify(data, null, 2));
    console.log(`\n🎵 Audio listo: ${data.first_audio_url}`);
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

testQuickStart();
