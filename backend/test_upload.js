import http from 'http';
import fs from 'fs';
import path from 'path';

const testUpload = async () => {
  console.log('Probando endpoint de subida...');
  
  const options = {
    hostname: '192.168.1.14',
    port: 3000,
    path: '/libros',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    }
  };

  const req = http.request(options, (res) => {
    console.log(`Status: ${res.statusCode}`);
    let data = '';
    
    res.on('data', (chunk) => {
      data += chunk;
    });
    
    res.on('end', () => {
      console.log('Response:', data);
    });
  });

  req.on('error', (error) => {
    console.error('Error:', error);
  });

  // Enviar request vacío para ver qué error retorna
  req.write(JSON.stringify({ titulo: 'Test' }));
  req.end();
};

testUpload();
