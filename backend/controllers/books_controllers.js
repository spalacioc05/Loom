import sql from '../db/client.js';
import { supabase } from '../config/supabase.js';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const pdfParse = require('pdf-parse');
import { PDFDocument } from 'pdf-lib';
import { processPdf } from '../workers/process_pdf.js';

// Obtener todos los libros disponibles con autores, géneros y categorías
export async function getAllBooks(req, res) {
	try {
		const books = await sql`
			SELECT 
				l.id_libro as id,
				l.titulo,
				l.descripcion,
				l.fecha_publicacion,
				l.portada,
				l.archivo,
				l.paginas,
				l.palabras,
				l.id_uploader as uploader_id,
				COALESCE(
					json_agg(
						DISTINCT jsonb_build_object('id', a.id_autor, 'nombre', a.nombre)
					) FILTER (WHERE a.id_autor IS NOT NULL),
					'[]'
				) as autores,
				COALESCE(
					json_agg(
						DISTINCT jsonb_build_object('id', g.id_genero, 'nombre', g.nombre)
					) FILTER (WHERE g.id_genero IS NOT NULL),
					'[]'
				) as generos,
				COALESCE(
					json_agg(
						DISTINCT jsonb_build_object('id', c.id_categoria, 'nombre', c.nombre)
					) FILTER (WHERE c.id_categoria IS NOT NULL),
					'[]'
				) as categorias
			FROM tbl_libros l
			LEFT JOIN tbl_libros_x_autores la ON l.id_libro = la.id_libro
			LEFT JOIN tbl_autores a ON la.id_autor = a.id_autor
			LEFT JOIN tbl_libros_x_generos lg ON l.id_libro = lg.id_libro
			LEFT JOIN tbl_generos g ON lg.id_genero = g.id_genero
			LEFT JOIN tbl_libros_x_categorias lc ON l.id_libro = lc.id_libro
			LEFT JOIN tbl_categorias c ON lc.id_categoria = c.id_categoria
			WHERE COALESCE(l.eliminado, false) = false
			GROUP BY l.id_libro, l.titulo, l.descripcion, l.fecha_publicacion, l.portada, l.archivo, l.paginas, l.palabras, l.id_uploader
			ORDER BY l.id_libro DESC
		`;
		res.json(books);
	} catch (error) {
		console.error('Error fetching books:', error);
		res.status(500).json({ error: 'Error fetching books' });
	}
}

// Obtener todas las categorías disponibles desde tbl_categorias
export async function getCategories(req, res) {
	try {
		const categorias = await sql`
			SELECT id_categoria as id, nombre, descripcion
			FROM tbl_categorias
			ORDER BY nombre
		`;
		
		res.json(categorias);
	} catch (error) {
		console.error('Error fetching categories:', error);
		res.status(500).json({ error: 'Error fetching categories' });
	}
}

// Obtener libros de la biblioteca personal de un usuario
export async function getUserLibrary(req, res) {
	try {
		const { userId } = req.params;
		
		if (!userId) {
			return res.status(400).json({ error: 'userId requerido' });
		}

		console.log(`📚 Consultando biblioteca (tbl_libros_x_usuarios) para usuario: ${userId}`);

		const books = await sql`
			SELECT 
				l.id_libro as id,
				l.titulo,
				l.descripcion,
				l.fecha_publicacion,
				l.portada,
				l.archivo,
				l.paginas,
				l.palabras,
				l.id_uploader as uploader_id,
				x.progreso as progreso,
				x.fecha_ultima_lectura,
				COALESCE(
					json_agg(
						DISTINCT jsonb_build_object('id', a.id_autor, 'nombre', a.nombre)
					) FILTER (WHERE a.id_autor IS NOT NULL),
					'[]'
				) as autores,
				COALESCE(
					json_agg(
						DISTINCT jsonb_build_object('id', g.id_genero, 'nombre', g.nombre)
					) FILTER (WHERE g.id_genero IS NOT NULL),
					'[]'
				) as generos,
				COALESCE(
					json_agg(
						DISTINCT jsonb_build_object('id', c.id_categoria, 'nombre', c.nombre)
					) FILTER (WHERE c.id_categoria IS NOT NULL),
					'[]'
				) as categorias
			FROM tbl_libros_x_usuarios x
			INNER JOIN tbl_libros l ON x.id_libro = l.id_libro
			LEFT JOIN tbl_libros_x_autores la ON l.id_libro = la.id_libro
			LEFT JOIN tbl_autores a ON la.id_autor = a.id_autor
			LEFT JOIN tbl_libros_x_generos lg ON l.id_libro = lg.id_libro
			LEFT JOIN tbl_generos g ON lg.id_genero = g.id_genero
			LEFT JOIN tbl_libros_x_categorias lc ON l.id_libro = lc.id_libro
			LEFT JOIN tbl_categorias c ON lc.id_categoria = c.id_categoria
			WHERE x.id_usuario = ${userId}::bigint AND COALESCE(l.eliminado, false) = false
			GROUP BY l.id_libro, l.titulo, l.descripcion, l.fecha_publicacion, l.portada, l.archivo, l.paginas, l.palabras, l.id_uploader, x.progreso, x.fecha_ultima_lectura
			ORDER BY x.fecha_ultima_lectura DESC NULLS LAST, l.id_libro DESC
		`;
		
		console.log(`✅ Encontrados ${books.length} libros en biblioteca`);
		res.json(books);
	} catch (error) {
		console.error('❌ Error fetching user library:', error);
		console.error('Error details:', error.message);
		
		// Si la tabla no existe, devolver array vacío en lugar de error
		if (error.message && error.message.includes('does not exist')) {
			console.log('⚠️ La tabla tbl_libros_x_usuarios no existe. Verifica tu esquema');
			return res.json([]);
		}
		
		res.status(500).json({ error: 'Error al obtener biblioteca del usuario' });
	}
}

// Agregar un libro a la biblioteca del usuario
export async function addToUserLibrary(req, res) {
	try {
		const { userId, bookId } = req.body;
		
		if (!userId || !bookId) {
			return res.status(400).json({ error: 'userId y bookId son requeridos' });
		}

		// Verificar si el libro existe
		const book = await sql`
			SELECT id_libro FROM tbl_libros WHERE id_libro = ${bookId}
		`;
		
		if (book.length === 0) {
			return res.status(404).json({ error: 'Libro no encontrado' });
		}

		// Verificar si ya existe relación
		const exists = await sql`
			SELECT 1 FROM tbl_libros_x_usuarios WHERE id_usuario = ${userId}::bigint AND id_libro = ${bookId}::bigint LIMIT 1
		`;
		if (exists.length > 0) {
			return res.status(200).json({ message: 'El libro ya estaba en tu biblioteca' });
		}

		await sql`
			INSERT INTO tbl_libros_x_usuarios (id_usuario, id_libro, fecha_ultima_lectura, progreso, tiempo_escucha)
			VALUES (${userId}::bigint, ${bookId}::bigint, NOW(), 0.0, 0)
		`;

		res.status(201).json({ message: 'Libro agregado a tu biblioteca' });
	} catch (error) {
		console.error('Error adding book to library:', error);
		res.status(500).json({ error: 'Error al agregar libro a biblioteca' });
	}
}

// Remover un libro de la biblioteca del usuario
export async function removeFromUserLibrary(req, res) {
	try {
		const { userId, bookId } = req.body;
		
		if (!userId || !bookId) {
			return res.status(400).json({ error: 'userId y bookId son requeridos' });
		}

		await sql`
			DELETE FROM tbl_libros_x_usuarios
			WHERE id_usuario = ${userId}::bigint AND id_libro = ${bookId}::bigint
		`;

		res.json({ message: 'Libro removido de tu biblioteca' });
	} catch (error) {
		console.error('Error removing book from library:', error);
		res.status(500).json({ error: 'Error al remover libro de biblioteca' });
	}
}

// Editar un libro (solo autor/uploader)
export async function updateBook(req, res) {
	try {
		const { id } = req.params;
		const { userId, titulo, descripcion } = req.body || {};
		if (!id) return res.status(400).json({ error: 'id es requerido' });
		if (!userId) return res.status(400).json({ error: 'userId es requerido' });

		const rows = await sql`SELECT id_libro, id_uploader FROM tbl_libros WHERE id_libro = ${id}::bigint LIMIT 1`;
		if (rows.length === 0) return res.status(404).json({ error: 'Libro no encontrado' });
		const book = rows[0];
		if (String(book.id_uploader || '') !== String(userId)) {
			return res.status(403).json({ error: 'No autorizado: solo el autor puede editar' });
		}
		await sql`
			UPDATE tbl_libros SET 
				titulo = COALESCE(${titulo}, titulo),
				descripcion = COALESCE(${descripcion}, descripcion)
			WHERE id_libro = ${id}::bigint
		`;
		return res.json({ message: 'Libro actualizado' });
	} catch (err) {
		console.error('Error updateBook:', err.message);
		return res.status(500).json({ error: 'Error actualizando libro', detail: err.message });
	}
}

// Eliminar (soft-delete) un libro (solo autor/uploader)
export async function deleteBook(req, res) {
	try {
		const { id } = req.params;
		const { userId } = req.body || {};
		const headerUser = req.headers['x-user-id'];
		const uid = userId || headerUser;
		if (!id) return res.status(400).json({ error: 'id es requerido' });
		if (!uid) return res.status(400).json({ error: 'userId requerido' });

		const rows = await sql`SELECT id_libro, id_uploader FROM tbl_libros WHERE id_libro = ${id}::bigint LIMIT 1`;
		if (rows.length === 0) return res.status(404).json({ error: 'Libro no encontrado' });
		const book = rows[0];
		if (String(book.id_uploader || '') !== String(uid)) {
			return res.status(403).json({ error: 'No autorizado: solo el autor puede eliminar' });
		}
		await sql`UPDATE tbl_libros SET eliminado = TRUE WHERE id_libro = ${id}::bigint`;
		return res.json({ message: 'Libro eliminado' });
	} catch (err) {
		console.error('Error deleteBook:', err.message);
		return res.status(500).json({ error: 'Error eliminando libro', detail: err.message });
	}
}

// Subir un nuevo libro con PDF
export async function uploadBook(req, res) {
	try {
		console.log('=== NUEVA REQUEST A /libros ===');
		console.log('Método:', req.method);
		console.log('Content-Type:', req.headers['content-type']);
		console.log('=== Iniciando upload de libro ===');
		console.log('Body:', req.body);
		console.log('Files:', req.files);
		
	const { titulo, descripcion, categoria } = req.body;
	// Identificador del usuario que sube el libro (opcional pero recomendado)
	// Acepta 'userId' o 'id_usuario' como alias y también cabecera 'x-user-id'
	const rawUserId = req.body.userId || req.body.id_usuario || req.headers['x-user-id'];
		const pdfFile = req.files?.pdf?.[0];
		const portadaFile = req.files?.portada?.[0];

		if (!pdfFile) {
			console.log('❌ Error: No se proporcionó archivo PDF');
			return res.status(400).json({ error: 'No se proporcionó un archivo PDF' });
		}

		if (!titulo) {
			console.log('❌ Error: Falta título');
			return res.status(400).json({ error: 'El título es requerido' });
		}

		// categoria ahora es un JSON string de array de IDs: "[1, 3, 5]"
		let categoriasIds = [];
		if (!categoria || !categoria.trim()) {
			console.log('❌ Error: Falta categoría');
			return res.status(400).json({ error: 'Al menos una categoría es requerida' });
		}
		
		try {
			categoriasIds = JSON.parse(categoria);
			if (!Array.isArray(categoriasIds) || categoriasIds.length === 0) {
				return res.status(400).json({ error: 'Debe seleccionar al menos una categoría' });
			}
		} catch (e) {
			return res.status(400).json({ error: 'Formato de categorías inválido' });
		}

		console.log('PDF recibido:', pdfFile.originalname, `(${pdfFile.size} bytes)`);
		if (portadaFile) {
			console.log('Portada recibida:', portadaFile.originalname, `(${portadaFile.size} bytes)`);
		}

		// Extraer información del PDF (número de páginas y palabras aproximadas)
		console.log('Analizando PDF...');
		console.log('Tamaño del buffer:', pdfFile.buffer.length);
		let numPaginas = null;
		let numPalabras = null;
		
		// Opciones avanzadas para extraer texto más consistente
		const pdfParseOptions = {
			pagerender: async (pageData) => {
				const textContent = await pageData.getTextContent({
					normalizeWhitespace: true,
					disableCombineTextItems: false,
				});
				// Unir ítems de texto con espacios para preservar palabras
				const text = textContent.items.map(i => i.str).join(' ');
				return text;
			},
		};

		try {
			const pdfData = await pdfParse(pdfFile.buffer, pdfParseOptions);
			numPaginas = pdfData.numpages;
			console.log('PDF parseado - numpages:', pdfData.numpages);
			
			// Contar palabras aproximadas del texto extraído
			if (pdfData.text) {
				const palabras = pdfData.text.trim().split(/\s+/).filter(p => p.length > 0);
				numPalabras = palabras.length;
				console.log('Texto extraído - primeros 100 chars:', pdfData.text.substring(0, 100));
				console.log('Total palabras:', numPalabras);
			}
			
			console.log(`✅ PDF analizado: ${numPaginas} páginas, ~${numPalabras} palabras`);
		} catch (pdfError) {
			console.error('⚠️ Error completo al extraer información del PDF:', pdfError);
			// Continuar sin esta información
		}

		// Fallback para contar páginas si pdf-parse no lo logró
		if (!numPaginas || !Number.isFinite(Number(numPaginas))) {
			try {
				const pdfDoc = await PDFDocument.load(pdfFile.buffer, { ignoreEncryption: true });
				numPaginas = pdfDoc.getPageCount();
				console.log('📄 Fallback (pdf-lib) page count:', numPaginas);
			} catch (e) {
				console.warn('⚠️ Fallback pdf-lib también falló:', e.message);
			}
		}

		// Asegurar valores numéricos por defecto si no se pudieron calcular
		numPaginas = Number.isFinite(Number(numPaginas)) ? Number(numPaginas) : 0;
		numPalabras = Number.isFinite(Number(numPalabras)) ? Number(numPalabras) : 0;
		if (numPalabras === 0) {
			console.log('ℹ️ No se extrajo texto del PDF. Guardando palabras = 0 (sin estimación).');
		}
		console.log(`Valores finales -> páginas: ${numPaginas}, palabras: ${numPalabras}`);

		// Obtener fecha actual
		const fechaActual = new Date().toISOString().split('T')[0]; // Formato: YYYY-MM-DD

				// Generar nombre único para el archivo y sanitizarlo (quitar acentos y caracteres inválidos)
				const timestamp = Date.now();
				// Normalizar y remover diacríticos (ñ, á, é, etc.)
				const safeBase = titulo
					.normalize('NFKD')
					.replace(/\p{Diacritic}/gu, '')
					.toLowerCase()
					// reemplazar cualquier caracter no alfanumérico por guión
					.replace(/[^a-z0-9]+/g, '-')
					// quitar guiones repetidos y guiones al inicio/final
					.replace(/^-+|-+$/g, '')
					.slice(0, 180); // limitar longitud

				const fileName = `${safeBase}-${timestamp}.pdf`;
				const filePath = `libros/${fileName}`;

		console.log('Subiendo archivo a Supabase Storage...');
		console.log('Bucket: archivos_libros');
		console.log('Path:', filePath);
		console.log('Tamaño:', pdfFile.size, 'bytes');

		// Subir PDF a Supabase Storage
		const { data: uploadData, error: uploadError } = await supabase.storage
			.from('archivos_libros')
			.upload(filePath, pdfFile.buffer, {
				contentType: 'application/pdf',
				upsert: false
			});

		if (uploadError) {
			console.error('Error uploading to Supabase:', uploadError);
			return res.status(500).json({ 
				error: 'Error al subir el archivo a Supabase',
				details: uploadError.message,
				supabaseError: uploadError
			});
		}

		console.log('Archivo subido exitosamente:', uploadData);

		// Obtener URL pública del archivo
		const { data: urlData } = supabase.storage
			.from('archivos_libros')
			.getPublicUrl(filePath);

		const archivoUrl = urlData.publicUrl;
		console.log('URL pública del PDF generada:', archivoUrl);

		// Subir portada si existe
		let portadaUrl = null;
		if (portadaFile) {
			console.log('Subiendo portada a Supabase Storage...');
			const portadaExt = portadaFile.originalname.split('.').pop();
			const portadaFileName = `${safeBase}-${timestamp}-portada.${portadaExt}`;
			const portadaPath = `portadas/${portadaFileName}`;

			const { data: portadaUploadData, error: portadaUploadError } = await supabase.storage
				.from('archivos_libros')
				.upload(portadaPath, portadaFile.buffer, {
					contentType: portadaFile.mimetype,
					upsert: false
				});

			if (portadaUploadError) {
				console.warn('⚠️ Error al subir portada:', portadaUploadError.message);
			} else {
				const { data: portadaUrlData } = supabase.storage
					.from('archivos_libros')
					.getPublicUrl(portadaPath);
				
				portadaUrl = portadaUrlData.publicUrl;
				console.log('✅ URL pública de la portada generada:', portadaUrl);
			}
		}

		// Insertar libro en la base de datos con todos los campos automáticos
		console.log('Insertando libro en la base de datos...');
	    const result = await sql`
			INSERT INTO tbl_libros (
				titulo, 
				descripcion, 
				fecha_publicacion, 
				archivo,
				portada,
				paginas,
					palabras,
					id_uploader
			)
			VALUES (
				${titulo}, 
				${descripcion || null}, 
				${fechaActual}, 
				${archivoUrl},
				${portadaUrl},
					${numPaginas},
					${numPalabras},
					${rawUserId ? String(rawUserId).trim() : null}::bigint
			)
			RETURNING *
		`;

		const newBook = result[0];
		console.log('✅ Libro insertado exitosamente:', newBook.id_libro);

		// Insertar relaciones con categorías
		console.log('Insertando categorías para el libro...');
		for (const catId of categoriasIds) {
			await sql`
				INSERT INTO tbl_libros_x_categorias (id_libro, id_categoria)
				VALUES (${newBook.id_libro}, ${catId})
			`;
		}
		console.log(`✅ ${categoriasIds.length} categoría(s) asociada(s)`);

		// Lanzar segmentación en background (no bloquear la respuesta)
		try {
			processPdf(newBook.id_libro)
				.then(() => console.log('✅ Segmentación completada para libro', newBook.id_libro))
				.catch(err => console.error('❌ Segmentación falló:', err.message));
		} catch (e) {
			console.warn('⚠️ No se pudo lanzar segmentación en background:', e.message);
		}

		// Si tenemos userId, agregar a la biblioteca del usuario automáticamente
		if (rawUserId) {
			try {
				// Forzar string y quitar espacios
				const userIdStr = String(rawUserId).trim();
				// Validación básica: numérico
				if (/^\d+$/.test(userIdStr)) {
					await sql`
						INSERT INTO tbl_libros_x_usuarios (id_usuario, id_libro, fecha_ultima_lectura, progreso, tiempo_escucha)
						VALUES (${userIdStr}::bigint, ${newBook.id_libro}::bigint, NOW(), 0.0, 0)
						ON CONFLICT (id_usuario, id_libro) DO NOTHING
					`;
					console.log(`📚 Libro ${newBook.id_libro} agregado a biblioteca de usuario ${userIdStr}`);
				} else {
					console.warn('⚠️ userId inválido, debe ser numérico. Recibido:', rawUserId);
				}
			} catch (e) {
				console.warn('⚠️ No se pudo agregar el libro a la biblioteca automáticamente:', e.message);
			}
		} else {
			console.log('ℹ️ No se envió userId; omitiendo auto-agregar a biblioteca.');
		}

		res.status(201).json({
			message: 'Libro subido exitosamente',
			book: {
				id: newBook.id_libro,
				titulo: newBook.titulo,
				descripcion: newBook.descripcion,
				fecha_publicacion: newBook.fecha_publicacion,
				archivo: newBook.archivo,
				paginas: newBook.paginas,
				palabras: newBook.palabras,
				uploader_id: newBook.id_uploader
			},
			addedToLibrary: Boolean(rawUserId)
		});

	} catch (error) {
		console.error('Error uploading book:', error);
		res.status(500).json({ 
			error: 'Error al subir el libro',
			details: error.message,
			stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
		});
	}
}
