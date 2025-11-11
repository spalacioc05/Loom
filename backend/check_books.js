import sql from './db/client.js';

async function checkBooks() {
  try {
    console.log('📚 Verificando libros en la base de datos...\n');
    
    // Ver últimos 5 libros subidos
    const books = await sql`
      SELECT id_libro, titulo, paginas, palabras, fecha_publicacion, archivo
      FROM tbl_libros
      ORDER BY id_libro DESC
      LIMIT 5
    `;
    
    console.log(`Total de libros encontrados: ${books.length}\n`);
    
    for (const book of books) {
      console.log(`ID: ${book.id_libro}`);
      console.log(`Título: ${book.titulo}`);
      console.log(`Páginas: ${book.paginas}`);
      console.log(`Palabras: ${book.palabras}`);
      console.log(`Archivo: ${book.archivo}`);
      
      // Verificar cuántos segmentos tiene
      const segments = await sql`
        SELECT COUNT(*) as total
        FROM tbl_segmentos s
        JOIN tbl_documentos d ON s.documento_id = d.id
        WHERE d.libro_id = ${book.id_libro}
      `;
      
      console.log(`Segmentos: ${segments[0].total}`);
      console.log('---\n');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

checkBooks();
