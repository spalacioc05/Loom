import 'dotenv/config';
import sql from './db/client.js';
import { generateAudio, estimateDuration } from './services/tts_provider.js';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function testVoices() {
  console.log('🎙️  Probando diferentes voces de Google TTS\n');
  
  try {
    // Obtener todas las voces activas
    const voices = await sql`
      SELECT id, proveedor, codigo_voz, idioma, configuracion 
      FROM tbl_voces 
      WHERE activo = true
      ORDER BY codigo_voz
      LIMIT 4
    `;
    
    console.log(`Encontradas ${voices.length} voces para probar\n`);
    
    const testText = "Hola, esta es una prueba de texto a voz. Cada voz debería sonar diferente.";
    
    for (const voice of voices) {
      console.log(`\n${'='.repeat(60)}`);
      console.log(`Probando: ${voice.codigo_voz} (${voice.idioma})`);
      console.log('='.repeat(60));
      
      try {
        const audioBuffer = await generateAudio(testText, voice.codigo_voz, voice.configuracion || {});
        const fileName = `test_voices/${voice.codigo_voz}_test.mp3`;
        
        console.log(`Subiendo a Supabase Storage: ${fileName}`);
        const { error: upErr } = await supabase.storage
          .from('audios_tts')
          .upload(fileName, audioBuffer, { 
            contentType: 'audio/mpeg', 
            upsert: true
          });
        
        if (upErr) throw upErr;
        
        const { data: urlData } = supabase.storage.from('audios_tts').getPublicUrl(fileName);
        console.log(`✅ Audio generado: ${audioBuffer.length} bytes`);
        console.log(`📍 URL: ${urlData.publicUrl}`);
        
      } catch (err) {
        console.error(`❌ Error con voz ${voice.codigo_voz}:`, err.message);
      }
    }
    
    console.log(`\n${'='.repeat(60)}`);
    console.log('✅ Prueba de voces completada');
    console.log('='.repeat(60));
    console.log('\nPuedes reproducir los archivos desde Supabase Storage:');
    console.log('Bucket: audios_tts');
    console.log('Carpeta: test_voices/');
    
  } catch (error) {
    console.error('❌ Error en prueba:', error.message);
    throw error;
  } finally {
    await sql.end();
  }
}

testVoices()
  .then(() => process.exit(0))
  .catch(() => process.exit(1));
