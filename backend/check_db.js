import postgres from 'postgres';

const connectionString = 'postgresql://postgres:administradores1234@db.yditubxizgubcntiysnh.supabase.co:5432/postgres';
const sql = postgres(connectionString, { ssl: 'require' });

async function checkDatabase() {
  try {
    console.log('🔍 Conectando a la base de datos...\n');

    // Ver todas las tablas
    console.log('📋 TABLAS EN LA BASE DE DATOS:');
    const tables = await sql`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      ORDER BY table_name;
    `;
    console.log(tables.map(t => `  - ${t.table_name}`).join('\n'));
    console.log('\n');

    // Ver estructura de la tabla tbl_libros
    console.log('📚 ESTRUCTURA DE LA TABLA "tbl_libros":');
    const columns = await sql`
      SELECT column_name, data_type, character_maximum_length, is_nullable, column_default
      FROM information_schema.columns 
      WHERE table_name = 'tbl_libros' AND table_schema = 'public'
      ORDER BY ordinal_position;
    `;
    
    if (columns.length > 0) {
      columns.forEach(col => {
        const maxLength = col.character_maximum_length ? `(${col.character_maximum_length})` : '';
        const nullable = col.is_nullable === 'YES' ? 'NULL' : 'NOT NULL';
        const defaultVal = col.column_default ? `DEFAULT ${col.column_default}` : '';
        console.log(`  ${col.column_name}: ${col.data_type}${maxLength} ${nullable} ${defaultVal}`);
      });
    } else {
      console.log('  ⚠️ La tabla "tbl_libros" no existe');
    }
    console.log('\n');

    // Ver datos de ejemplo
    console.log('📖 DATOS EN LA TABLA "tbl_libros" (con estado = 1):');
    const booksWithState = await sql`SELECT * FROM tbl_libros WHERE id_estado = 1 LIMIT 5`;
    console.log(`  Total con estado = 1: ${booksWithState.length}`);
    
    console.log('\n📖 TODOS LOS LIBROS (sin filtro):');
    const allBooks = await sql`SELECT id_libro, titulo, portada, archivo, id_estado FROM tbl_libros ORDER BY id_libro DESC LIMIT 10`;
    console.log(`  Total de registros: ${allBooks.length}`);
    if (allBooks.length > 0) {
      console.log('\n  Primeros 10 registros:');
      allBooks.forEach((book, idx) => {
        console.log(`\n  ${idx + 1}. ID: ${book.id_libro} - ${book.titulo}`);
        console.log(`     Estado: ${book.id_estado}`);
        console.log(`     Portada: ${book.portada ? 'Sí' : 'No'}`);
        console.log(`     Archivo: ${book.archivo ? 'Sí' : 'No'}`);
      });
    }
    
    // Ver estructura de tablas relacionadas
    console.log('\n📚 ESTRUCTURA DE LA TABLA "tbl_autores":');
    const autoresColumns = await sql`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'tbl_autores' AND table_schema = 'public'
      ORDER BY ordinal_position;
    `;
    autoresColumns.forEach(col => {
      console.log(`  ${col.column_name}: ${col.data_type}`);
    });
    
    console.log('\n📚 ESTRUCTURA DE LA TABLA "tbl_generos":');
    const generosColumns = await sql`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'tbl_generos' AND table_schema = 'public'
      ORDER BY ordinal_position;
    `;
    generosColumns.forEach(col => {
      console.log(`  ${col.column_name}: ${col.data_type}`);
    });
    
    console.log('\n📚 ESTRUCTURA DE LA TABLA "tbl_libros_x_autores":');
    const librosAutoresColumns = await sql`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'tbl_libros_x_autores' AND table_schema = 'public'
      ORDER BY ordinal_position;
    `;
    librosAutoresColumns.forEach(col => {
      console.log(`  ${col.column_name}: ${col.data_type}`);
    });

  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await sql.end();
  }
}

checkDatabase();
