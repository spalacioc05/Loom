import 'dotenv/config';
import sql from './db/client.js';

async function testConnection() {
  try {
    console.log('🔌 Probando conexión a base de datos...');
    const result = await sql`SELECT current_database(), current_user`;
    console.log('✅ Conexión exitosa a:', result[0].current_database);
    console.log('   Usuario:', result[0].current_user);
    
    // Verificar si existe la tabla tbl_usuarios
    const tables = await sql`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' AND table_name = 'tbl_usuarios'
    `;
    
    if (tables.length > 0) {
      console.log('✅ Tabla tbl_usuarios existe');
      
      // Verificar columnas
      const columns = await sql`
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'tbl_usuarios'
        ORDER BY ordinal_position
      `;
      
      console.log('\n📊 Columnas de tbl_usuarios:');
      columns.forEach(col => {
        console.log(`   - ${col.column_name}: ${col.data_type}`);
      });
      
      const hasFirebaseUid = columns.some(c => c.column_name === 'firebase_uid');
      if (hasFirebaseUid) {
        console.log('\n✅ Columna firebase_uid YA EXISTE');
      } else {
        console.log('\n⚠️  Columna firebase_uid NO EXISTE - se debe ejecutar migración');
      }
    } else {
      console.log('❌ Tabla tbl_usuarios NO existe');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  } finally {
    await sql.end();
    process.exit(0);
  }
}

testConnection();
