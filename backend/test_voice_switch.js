import 'dotenv/config';
import sql from './db/client.js';

async function testVoiceSwitch() {
  console.log('🎙️  Probando cambio de voces\n');
  
  try {
    // Obtener voces disponibles
    const voices = await sql`
      SELECT id, codigo_voz, idioma 
      FROM tbl_voces 
      WHERE activo = true
      ORDER BY codigo_voz
    `;
    
    console.log(`Voces disponibles: ${voices.length}\n`);
    
    // Agrupar por tipo
    const female = voices.filter(v => v.codigo_voz.includes('Female'));
    const male = voices.filter(v => v.codigo_voz.includes('Male'));
    
    console.log('═'.repeat(60));
    console.log('VOCES FEMENINAS (Lenta/Clara):');
    console.log('═'.repeat(60));
    female.forEach((v, i) => {
      console.log(`${(i + 1).toString().padStart(2)}. ${v.codigo_voz.padEnd(20)} [${v.idioma}]`);
      console.log(`    ID: ${v.id}`);
    });
    
    console.log('\n' + '═'.repeat(60));
    console.log('VOCES MASCULINAS (Normal/Rápida):');
    console.log('═'.repeat(60));
    male.forEach((v, i) => {
      console.log(`${(i + 1).toString().padStart(2)}. ${v.codigo_voz.padEnd(20)} [${v.idioma}]`);
      console.log(`    ID: ${v.id}`);
    });
    
    console.log('\n' + '═'.repeat(60));
    console.log('PRUEBA DE CAMBIO DE VOZ:');
    console.log('═'.repeat(60));
    
    const libro2 = 2;
    const voice1 = female[0]; // Primera voz femenina
    const voice2 = male[0];   // Primera voz masculina
    
    console.log(`\nLibro: ${libro2}`);
    console.log(`Voz 1: ${voice1.codigo_voz} (${voice1.id})`);
    console.log(`Voz 2: ${voice2.codigo_voz} (${voice2.id})`);
    
    // Verificar audios existentes
    const audios1 = await sql`
      SELECT COUNT(*)::int as count
      FROM tbl_audios
      WHERE voz_id = ${voice1.id}
    `;
    
    const audios2 = await sql`
      SELECT COUNT(*)::int as count
      FROM tbl_audios
      WHERE voz_id = ${voice2.id}
    `;
    
    console.log(`\nAudios con ${voice1.codigo_voz}: ${audios1[0].count}`);
    console.log(`Audios con ${voice2.codigo_voz}: ${audios2[0].count}`);
    
    console.log('\n✅ Sistema listo para cambio de voces');
    console.log('\n💡 Para probar en el frontend:');
    console.log('   1. Abre un libro');
    console.log('   2. Toca el chip de voz');
    console.log('   3. Selecciona una voz diferente');
    console.log('   4. La app regenerará el audio con la nueva voz y reproducirá automáticamente');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await sql.end();
  }
}

testVoiceSwitch();
