import dotenv from 'dotenv';
dotenv.config();

import { processPdf } from './workers/process_pdf.js';

const libroId = parseInt(process.argv[2]) || 83;

console.log(`🔄 Procesando libro ID: ${libroId}\n`);

try {
  await processPdf(libroId);
  console.log('\n✅ Procesamiento completado');
  process.exit(0);
} catch (error) {
  console.error('\n❌ Error:', error.message);
  process.exit(1);
}
