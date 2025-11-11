import sql from '../db/client.js';

export async function ensureUser(req, res) {
  try {
    const { firebaseUid, email, displayName, photoUrl } = req.body || {};
    
    if (!firebaseUid && !email) {
      return res.status(400).json({ error: 'Se requiere firebaseUid o email' });
    }

    console.log('ensureUser:', firebaseUid, email);

    if (firebaseUid) {
      const existing = await sql`SELECT id_usuario FROM tbl_usuarios WHERE firebase_uid = ${firebaseUid} LIMIT 1`;
      if (existing.length > 0) {
        console.log('Usuario existente:', existing[0].id_usuario);
        return res.json({ id_usuario: existing[0].id_usuario });
      }
    }

    if (email) {
      const existing = await sql`SELECT id_usuario FROM tbl_usuarios WHERE correo = ${email} LIMIT 1`;
      if (existing.length > 0) {
        console.log('Usuario existente (email):', existing[0].id_usuario);
        if (firebaseUid) {
          await sql`UPDATE tbl_usuarios SET firebase_uid = ${firebaseUid} WHERE id_usuario = ${existing[0].id_usuario}`;
        }
        return res.json({ id_usuario: existing[0].id_usuario });
      }
    }

    console.log('Creando usuario...');
    const inserted = await sql`
      INSERT INTO tbl_usuarios (firebase_uid, correo, nombre, foto_perfil, fecha_registro)
      VALUES (${firebaseUid || null}, ${email || null}, ${displayName || 'Usuario'}, ${photoUrl || null}, NOW())
      RETURNING id_usuario
    `;
    
    console.log('Usuario creado:', inserted[0].id_usuario);
    return res.status(201).json({ id_usuario: inserted[0].id_usuario });
    
  } catch (err) {
    console.error('Error ensureUser:', err);
    return res.status(500).json({ error: 'Error al asegurar usuario', detail: err.message });
  }
}

export async function getUserByFirebase(req, res) {
  try {
    const { firebaseUid } = req.params;
    if (!firebaseUid) return res.status(400).json({ error: 'firebaseUid requerido' });
    const rows = await sql`SELECT id_usuario FROM tbl_usuarios WHERE firebase_uid = ${firebaseUid} LIMIT 1`;
    if (rows.length === 0) return res.status(404).json({ error: 'Usuario no encontrado' });
    return res.json({ id_usuario: rows[0].id_usuario });
  } catch (err) {
    console.error('Error getUserByFirebase:', err);
    return res.status(500).json({ error: 'Error al obtener usuario', detail: err.message });
  }
}
