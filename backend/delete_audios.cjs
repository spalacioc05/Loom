require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function deleteOldAudios(libroId) {
  try {
    console.log(`🗑️  Eliminando audios antiguos del libro ${libroId}...`);

    // Obtener documento
    const { data: doc } = await supabase
      .from('tbl_documentos')
      .select('id')
      .eq('libro_id', libroId)
      .single();

    if (!doc) {
      console.log('❌ No se encontró documento');
      return;
    }

    // Eliminar audios
    const { error } = await supabase
      .from('tbl_audios')
      .delete()
      .eq('documento_id', doc.id);

    if (error) {
      console.error('❌ Error:', error);
    } else {
      console.log('✅ Audios eliminados de la BD');
      console.log('📁 Nota: Los archivos MP3 en Supabase Storage quedan ahí (puedes borrarlos manualmente si quieres)');
    }
  } catch (error) {
    console.error('Error:', error);
  }
}

const libroId = parseInt(process.argv[2]);
if (!libroId) {
  console.error('Uso: node delete_audios.cjs <libro_id>');
  process.exit(1);
}

deleteOldAudios(libroId);
