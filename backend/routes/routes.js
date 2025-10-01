import { Router } from 'express';
import { getAllBooks } from '../controllers/books_controllers.js';

const router = Router();

router.get('/disponibles', getAllBooks);

export default router;