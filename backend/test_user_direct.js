import sql from './db/client.js';

console.log('🧪 Probando endpoint /usuarios/ensure...\n');

const testUser = {
  firebaseUid: 'DfszewtL6HQgFAimhBm6OC5WCVJ3',
  email: 'doomerfamily666@gmail.com',
  displayName: 'doomer family',
  photoUrl: null
};

console.log('Datos de prueba:', testUser);

async function testEnsure() {
  try {
    // Buscar existente
    const existing = await sql`
      SELECT id_usuario FROM tbl_usuarios 
      WHERE firebase_uid = ${testUser.firebaseUid} 
      LIMIT 1
    `;
    
    if (existing.length > 0) {
      console.log('✅ Usuario YA existe:', existing[0].id_usuario);
      process.exit(0);
    }

    // Crear nuevo
    console.log('➕ Creando usuario...');
    const inserted = await sql`
      INSERT INTO tbl_usuarios (firebase_uid, correo, nombre, foto_perfil, fecha_registro)
      VALUES (
        ${testUser.firebaseUid},
        ${testUser.email},
        ${testUser.displayName},
        ${testUser.photoUrl},
        NOW()
      )
      RETURNING id_usuario
    `;
    
    console.log('✅ Usuario creado:', inserted[0].id_usuario);
    process.exit(0);
  } catch (err) {
    console.error('❌ Error:', err);
    process.exit(1);
  }
}

testEnsure();
