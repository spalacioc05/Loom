import dotenv from 'dotenv';
import postgres from 'postgres';
import path from 'path';
import { fileURLToPath } from 'url';

// Cargar .env desde backend/.env sin importar desde dónde se ejecute el proceso
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
	console.error('❌ DATABASE_URL no está definido. Verifica backend/.env');
}
const ssl = process.env.PGSSL === 'disable' ? undefined : 'require';
const sql = postgres(connectionString, { ssl });

export default sql
