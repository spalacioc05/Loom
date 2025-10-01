import sql from '../db/client.js';

// Obtener todos los libros disponibles
export async function getAllBooks(req, res) {
	try {
		const books = await sql`select * from "Libros"`;
		res.json(books);
	} catch (error) {
		console.error('Error fetching books:', error);
		res.status(500).json({ error: 'Error fetching books' });
	}
}
