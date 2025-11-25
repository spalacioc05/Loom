import { Router } from 'express';
import { 
  getAllBooks, 
  uploadBook, 
  getUserLibrary, 
  addToUserLibrary, 
  removeFromUserLibrary,
  updateBook,
  deleteBook,
  getCategories
} from '../controllers/books_controllers.js';
import { ensureUser, getUserByFirebase } from '../controllers/user_controllers.js';
import { 
  getVoices, 
  getPlaylist, 
  getSegmentAudio, 
  saveProgress, 
  getProgress,
  getBookAudios,
  quickStartBook
} from '../controllers/tts_controllers.js';
import multer from 'multer';
import { healthCheck } from '../controllers/health_controller.js';
import { processPdf } from '../workers/process_pdf.js';
import pkg from 'pg';
const { Pool } = pkg;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const router = Router();

// Configurar multer para almacenar archivos en memoria
const storage = multer.memoryStorage();
const upload = multer({ 
	storage: storage,
	limits: {
		fileSize: 50 * 1024 * 1024 // Límite de 50MB
	}
});

router.get('/disponibles', getAllBooks);

// Obtener categorías disponibles
router.get('/categorias', getCategories);

// Biblioteca de usuario
router.get('/biblioteca/:userId', getUserLibrary);
router.post('/biblioteca/agregar', addToUserLibrary);
router.delete('/biblioteca/remover', removeFromUserLibrary);

// Health check
router.get('/health', healthCheck);

// Ping rápido para diagnóstico de conectividad
router.get('/ping', (req, res) => {
  res.json({ ok: true, time: new Date().toISOString() });
});

// Asegurar usuario (upsert) y devolver id_usuario
router.post('/usuarios/ensure', ensureUser);

// Obtener usuario por firebaseUid (sin crear)
router.get('/usuarios/by-firebase/:firebaseUid', getUserByFirebase);

// Endpoint de prueba para verificar que POST funciona
router.post('/test', (req, res) => {
	console.log('Test endpoint hit!');
	res.json({ message: 'POST works!' });
});

// Endpoint para subir libro (PDF + portada opcional)
router.post('/libros', upload.fields([
	{ name: 'pdf', maxCount: 1 },
	{ name: 'portada', maxCount: 1 }
]), uploadBook);

// Editar y eliminar libro (solo autor/uploader)
router.put('/libros/:id', updateBook);
router.delete('/libros/:id', deleteBook);

// === Endpoints TTS ===
// Obtener lista de voces disponibles
router.get('/voices', getVoices);

// Quick-start: Genera y devuelve el primer audio inmediatamente
router.post('/tts/libro/:libroId/quick-start', quickStartBook);

// Generar playlist de segmentos
router.post('/tts/playlist', getPlaylist);

// Obtener audio de un segmento específico
router.get('/tts/segment', getSegmentAudio);

// Obtener todas las URLs de audio de un libro
router.get('/tts/libro/:libroId/audios', getBookAudios);

// Guardar progreso de reproducción
router.post('/progress', saveProgress);

// Obtener último progreso
router.get('/progress', getProgress);

// === ADMIN: Re-procesar libros ===
// Re-procesar un libro específico o todos los que no tengan segmentos
router.post('/admin/reprocess-books', async (req, res) => {
  try {
    const { libroId } = req.body;
    
    if (libroId) {
      // Re-procesar libro específico
      console.log(`🔄 Re-procesando libro ${libroId}...`);
      processPdf(libroId)
        .then(() => console.log(`✅ Libro ${libroId} re-procesado`))
        .catch(err => console.error(`❌ Error re-procesando libro ${libroId}:`, err));
      
      res.json({ message: `Libro ${libroId} encolado para re-procesamiento` });
    } else {
      // Buscar todos los libros sin segmentos usando pool
      const result = await pool.query(`
        SELECT l.id_libro, l.titulo
        FROM tbl_libros l
        LEFT JOIN tbl_documentos d ON l.id_libro = d.libro_id
        LEFT JOIN tbl_segmentos s ON d.id = s.documento_id
        WHERE l.archivo IS NOT NULL
        GROUP BY l.id_libro, l.titulo
        HAVING COUNT(s.id) = 0 OR MAX(d.estado) IN ('error', 'procesando')
      `);
      
      const libros = result.rows;
      console.log(`📋 Encontrados ${libros.length} libros sin segmentos`);
      
      for (const libro of libros) {
        console.log(`🔄 Encolando libro ${libro.id_libro}: ${libro.titulo}`);
        processPdf(libro.id_libro)
          .then(() => console.log(`✅ Libro ${libro.id_libro} procesado`))
          .catch(err => console.error(`❌ Error libro ${libro.id_libro}:`, err.message));
        
        // Delay de 2s entre libros para no saturar
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
      
      res.json({ 
        message: `${libros.length} libros encolados para procesamiento`,
        libros: libros.map(l => ({ id: l.id_libro, titulo: l.titulo }))
      });
    }
  } catch (error) {
    console.error('Error en reprocess-books:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;