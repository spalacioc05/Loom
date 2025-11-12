import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { generateAudio } from './services/free_tts.js';

// Simple script to compare two processed voices after pitch/speed transforms.
// Generates audio for the same text with a female and a male voice variant.

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function run() {
  const text = 'Hola, esta es una breve prueba para comparar el tono y velocidad entre voces.';
  const femaleVoice = 'es_female_2';
  const maleVoice = 'es_male_2';

  console.log('🎧 Generando muestras para comparación de pitch/speed');
  console.log('Texto base:', text);

  const femaleBuf = await generateAudio(text, femaleVoice, {});
  const maleBuf = await generateAudio(text, maleVoice, {});

  console.log(`✅ Female (${femaleVoice}) bytes:`, femaleBuf.length);
  console.log(`✅ Male   (${maleVoice}) bytes:`, maleBuf.length);

  // Upload both for manual listening
  const folder = 'pitch_test';
  const files = [
    { name: `${folder}/${femaleVoice}.mp3`, buf: femaleBuf },
    { name: `${folder}/${maleVoice}.mp3`, buf: maleBuf },
  ];

  for (const f of files) {
    const { error } = await supabase.storage.from('audios_tts').upload(f.name, f.buf, {
      contentType: 'audio/mpeg', upsert: true,
    });
    if (error) {
      console.error('❌ Upload error', f.name, error.message);
    } else {
      const { data } = supabase.storage.from('audios_tts').getPublicUrl(f.name);
      console.log(`📍 ${f.name} URL: ${data.publicUrl}`);
    }
  }

  console.log('\nEscucha las diferencias y confirma si el cambio de pitch/speed es perceptible.');
}

run().then(() => process.exit(0)).catch(err => {
  console.error('Script error', err);
  process.exit(1);
});
