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

export default router;