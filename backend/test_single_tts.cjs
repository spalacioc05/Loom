require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

// Importar función ES module desde CommonJS
async function generateSpeechFromText(text, voiceCode) {
  const module = await import('./services/azure_tts.js');
  return module.generateAudio(text, voiceCode);
}

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function testSingleSegment() {
  try {
    console.log('🧪 Probando generación de TTS para UN segmento...\n');

    // 1. Obtener el primer segmento del libro 83
    const { data: segmento, error: segError } = await supabase
      .from('tbl_segmentos')
      .select('id, orden, texto, documento_id')
      .eq('documento_id', 'd3f9f276-bbe6-4d32-aef1-c8ede7a79b5f')
      .eq('orden', 1)
      .single();

    if (segError || !segmento) {
      throw new Error('No se encontró el segmento 1');
    }

    console.log(`📝 Segmento ${segmento.orden}`);
    console.log(`   Texto (primeros 100 chars): ${segmento.texto.substring(0, 100)}...`);
    console.log(`   Longitud: ${segmento.texto.length} caracteres\n`);

    // 2. Obtener voz
    const { data: voz } = await supabase
      .from('tbl_voces')
      .select('*')
      .eq('activo', true)
      .limit(1)
      .single();

    console.log(`🗣️  Voz: ${voz.codigo_voz}\n`);

    // 3. Verificar si el bucket existe
    console.log('🔍 Verificando bucket "audios_tts"...');
    const { data: buckets, error: bucketListError } = await supabase.storage.listBuckets();
    
    if (bucketListError) {
      console.error('❌ Error listando buckets:', bucketListError);
      throw bucketListError;
    }

    const bucketExists = buckets.some(b => b.name === 'audios_tts');
    
    if (!bucketExists) {
      console.log('📦 Creando bucket "audios_tts"...');
      const { error: createError } = await supabase.storage.createBucket('audios_tts', {
        public: true
      });
      
      if (createError) {
        console.error('❌ Error creando bucket:', createError);
        throw createError;
      }
      console.log('✅ Bucket creado exitosamente\n');
    } else {
      console.log('✅ Bucket ya existe\n');
    }

    // 4. Generar audio
    console.log('🔊 Generando audio con Azure TTS...');
    const audioBuffer = await generateSpeechFromText(
      segmento.texto,
      voz.codigo_voz
    );

    console.log(`✅ Audio generado: ${audioBuffer.length} bytes\n`);

    // 5. Subir a Supabase Storage
    const fileName = `libro_83/segmento_${segmento.orden}.mp3`;
    console.log(`📤 Subiendo a: audios_tts/${fileName}`);
    
    const { data: uploadData, error: uploadError } = await supabase.storage
      .from('audios_tts')
      .upload(fileName, audioBuffer, {
        contentType: 'audio/mpeg',
        upsert: true
      });

    if (uploadError) {
      console.error('❌ Error subiendo:', uploadError);
      throw uploadError;
    }

    console.log('✅ Archivo subido exitosamente\n');

    // 6. Obtener URL pública
    const { data: urlData } = supabase.storage
      .from('audios_tts')
      .getPublicUrl(fileName);

    console.log(`🔗 URL pública: ${urlData.publicUrl}\n`);

    // 7. Guardar en tbl_audios
    console.log('💾 Guardando en tbl_audios...');
    const { error: insertError } = await supabase
      .from('tbl_audios')
      .insert({
        documento_id: segmento.documento_id,
        segmento_id: segmento.id,
        voz_id: voz.id,
        audio_url: urlData.publicUrl,
        duracion_ms: 0
      });

    if (insertError) {
      console.error('❌ Error guardando:', insertError);
      throw insertError;
    }

    console.log('✅ Registro guardado en BD\n');
    console.log('🎉 ¡PRUEBA EXITOSA! El audio se generó, subió y guardó correctamente.');
    console.log(`\n🎵 Puedes reproducir el audio desde: ${urlData.publicUrl}`);

  } catch (error) {
    console.error('\n❌ Error:', error);
    process.exit(1);
  }
}

testSingleSegment();
