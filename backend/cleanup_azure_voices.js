import 'dotenv/config';
import sql from './db/client.js';

async function cleanupAzureVoices() {
  console.log('🧹 Eliminando voces de Azure de la base de datos...\n');
  
  try {
    // Contar voces de Azure antes
    const beforeCount = await sql`
      SELECT COUNT(*)::int as count
      FROM tbl_voces 
      WHERE proveedor = 'azure'
    `;
    
    console.log(`Voces de Azure encontradas: ${beforeCount[0].count}`);
    
    if (beforeCount[0].count === 0) {
      console.log('✅ No hay voces de Azure para eliminar');
      return;
    }
    
    // Eliminar voces de Azure
    console.log('Eliminando...');
    await sql`
      DELETE FROM tbl_voces 
      WHERE proveedor = 'azure'
    `;
    
    console.log('✅ Voces de Azure eliminadas exitosamente\n');
    
    // Mostrar voces restantes
    const remaining = await sql`
      SELECT proveedor, codigo_voz, idioma 
      FROM tbl_voces 
      WHERE activo = true
      ORDER BY proveedor, idioma, codigo_voz
    `;
    
    console.log(`🎙️  Voces disponibles (${remaining.length}):`);
    remaining.forEach(v => {
      console.log(`   ${v.proveedor.padEnd(8)} ${v.codigo_voz.padEnd(20)} ${v.idioma}`);
    });
    
  } catch (error) {
    console.error('❌ Error eliminando voces:', error.message);
    throw error;
  } finally {
    await sql.end();
  }
}

cleanupAzureVoices()
  .then(() => process.exit(0))
  .catch(() => process.exit(1));
