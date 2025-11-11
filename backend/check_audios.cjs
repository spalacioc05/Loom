require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

(async () => {
  // Contar audios
  const { count, error: countError } = await supabase
    .from('tbl_audios')
    .select('id', { count: 'exact' })
    .eq('documento_id', 'd3f9f276-bbe6-4d32-aef1-c8ede7a79b5f');

  if (countError) {
    console.error('Error:', countError);
    return;
  }

  console.log(`Total de audios generados: ${count}`);
  console.log(`\nEstado del libro 83:`);
  console.log(`- Segmentos totales: 96`);
  console.log(`- Audios generados: ${count}`);
  console.log(`- Completitud: ${Math.round(count / 96 * 100)}%\n`);

  // Obtener URLs de muestra
  const { data: audios } = await supabase
    .from('tbl_audios')
    .select('audio_url, segmento_id')
    .eq('documento_id', 'd3f9f276-bbe6-4d32-aef1-c8ede7a79b5f')
    .limit(3);

  console.log('Primeros 3 audios:');
  audios.forEach((a, i) => {
    console.log(`${i + 1}. ${a.audio_url}`);
  });
})();
