import { createRequire } from 'module';
import fs from 'fs';

const require = createRequire(import.meta.url);
const pdfParse = require('pdf-parse');

async function test() {
  // Leer el test_audio que no existe, usar cualquier PDF del proyecto
  const testPdfPath = 'test_audio.mp3'; // Este no es PDF, solo para test
  
  console.log('Tipo de pdf-parse require:', typeof pdfParse);
  console.log('¿Es función?', typeof pdfParse === 'function');
  console.log('Propiedades:', Object.keys(pdfParse));
}

test();
