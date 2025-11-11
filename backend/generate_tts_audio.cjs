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

async function generateTTSForBook(libroId) {
  try {
    console.log(`🎙️  Generando TTS para libro ${libroId}...\n`);

    // 1. Obtener documento
    const { data: documento, error: docError } = await supabase
      .from('tbl_documentos')
      .select('id')
      .eq('libro_id', libroId)
      .single();

    if (docError || !documento) {
      throw new Error(`No se encontró documento para libro ${libroId}`);
    }

    console.log(`📄 Documento ID: ${documento.id}`);

    // 2. Obtener voz
    const { data: voz, error: vozError } = await supabase
      .from('tbl_voces')
      .select('*')
      .eq('activo', true)
      .limit(1)
      .single();

    if (vozError || !voz) {
      throw new Error('No se encontró voz activa');
    }

    console.log(`🗣️  Voz: ${voz.codigo_voz} (${voz.idioma})\n`);

    // 3. Obtener segmentos (SALTAR segmento 0 = metadata)
    const { data: segmentos, error: segError } = await supabase
      .from('tbl_segmentos')
      .select('id, orden, texto, documento_id')
      .eq('documento_id', documento.id)
      .gt('orden', 0)  // Solo segmentos > 0 (sin metadata)
      .order('orden', { ascending: true });

    if (segError || !segmentos || segmentos.length === 0) {
      throw new Error('No se encontraron segmentos');
    }

    console.log(`📝 Total de segmentos: ${segmentos.length}`);
    console.log(`⏳ Generando audios...\n`);

    let generados = 0;
    let errores = 0;

    for (const segmento of segmentos) {
      try {
        // Verificar si ya existe audio para este segmento
        const { data: existente } = await supabase
          .from('tbl_audios')
          .select('id')
          .eq('segmento_id', segmento.id)
          .eq('voz_id', voz.id)
          .single();

        if (existente) {
          console.log(`⏭️  Segmento ${segmento.orden} ya tiene audio`);
          continue;
        }

        // Generar audio con Azure TTS
        console.log(`🔊 Generando segmento ${segmento.orden}/${segmentos.length}...`);
        
        const audioBuffer = await generateSpeechFromText(
          segmento.texto,
          voz.codigo_voz
        );

        // Subir a Supabase Storage
        const fileName = `libro_${libroId}/segmento_${segmento.orden}.mp3`;
        const { error: uploadError } = await supabase.storage
          .from('audios_tts')
          .upload(fileName, audioBuffer, {
            contentType: 'audio/mpeg',
            upsert: true
          });

        if (uploadError) {
          throw uploadError;
        }

        // Obtener URL pública
        const { data: urlData } = supabase.storage
          .from('audios_tts')
          .getPublicUrl(fileName);

        // Guardar en tbl_audios
        const { error: insertError } = await supabase
          .from('tbl_audios')
          .insert({
            documento_id: segmento.documento_id,
            segmento_id: segmento.id,
            voz_id: voz.id,
            audio_url: urlData.publicUrl,
            duracion_ms: 0 // Se podría calcular
          });

        if (insertError) {
          throw insertError;
        }

        generados++;
        console.log(`✅ Segmento ${segmento.orden} completado`);

      } catch (err) {
        errores++;
        console.error(`❌ Error en segmento ${segmento.orden}:`, err.message);
      }
    }

    console.log(`\n🎉 Proceso finalizado:`);
    console.log(`   ✅ Audios generados: ${generados}`);
    console.log(`   ❌ Errores: ${errores}`);
    console.log(`   📊 Total: ${segmentos.length}`);

  } catch (error) {
    console.error('❌ Error general:', error);
    process.exit(1);
  }
}

// Ejecutar con el libro pasado como argumento
const libroId = parseInt(process.argv[2]);
if (!libroId) {
  console.error('❌ Uso: node generate_tts_audio.js <libro_id>');
  process.exit(1);
}

generateTTSForBook(libroId);
