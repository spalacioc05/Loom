require('dotenv').config();

async function testEndpoint() {
  try {
    const response = await fetch('http://localhost:3000/tts/libro/83/audios');
    const data = await response.json();
    
    console.log('=== RESPUESTA DEL ENDPOINT ===');
    console.log(`Libro ID: ${data.libro_id}`);
    console.log(`Documento ID: ${data.documento_id}`);
    console.log(`Total segmentos: ${data.total_segmentos}`);
    console.log(`Audios generados: ${data.audios_generados}`);
    console.log(`Progreso: ${data.progreso_porcentaje}%`);
    console.log(`\nPrimeros 3 audios:`);
    data.audios.slice(0, 3).forEach((audio, i) => {
      console.log(`${i + 1}. Segmento ${audio.orden}: ${audio.audio_url ? 'LISTO' : 'PENDIENTE'}`);
      if (audio.audio_url) {
        console.log(`   URL: ${audio.audio_url.substring(0, 80)}...`);
      }
    });
  } catch (error) {
    console.error('Error:', error.message);
  }
}

testEndpoint();
