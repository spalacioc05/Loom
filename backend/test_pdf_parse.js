import { createRequire } from 'module';
const require = createRequire(import.meta.url);

const pdfParse = require('pdf-parse');

console.log('Type of pdfParse:', typeof pdfParse);
console.log('pdfParse:', pdfParse);
console.log('pdfParse.default:', pdfParse.default);
