
import express from "express";
import sql from './db/client.js';
import cors from 'cors';
import morgan from 'morgan';
import os from 'os';

const app = express();
const PORT = process.env.PORT || 3000;

import authRoute from './routes/routes.js';

// Middlewares
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));
app.use(morgan('dev'));
app.use(express.json());

app.use('/', authRoute);

// Endpoint simple de salud para detección desde frontend
app.get('/ping', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

const server = app.listen(PORT, '0.0.0.0', async () => {
  // Obtener IP local de la PC
  const networkInterfaces = os.networkInterfaces();
  let localIP = 'localhost';
  
  for (const interfaceName of Object.keys(networkInterfaces)) {
    for (const net of networkInterfaces[interfaceName]) {
      // Buscar IPv4 que no sea localhost
      if (net.family === 'IPv4' && !net.internal) {
        localIP = net.address;
        break;
      }
    }
  }

  console.log('\n🚀 ════════════════════════════════════════════════════');
  console.log(`   Backend corriendo en puerto ${PORT}`);
  console.log('   ════════════════════════════════════════════════════');
  console.log(`   📱 Desde el celular usa: http://${localIP}:${PORT}`);
  console.log(`   💻 Desde esta PC usa:    http://localhost:${PORT}`);
  console.log('   ════════════════════════════════════════════════════\n');
  
  try {
    const result = await sql`SELECT NOW()`;
    console.log('✅ PostgreSQL conectado! Current time:', result[0].now);
  } catch (err) {
    console.error('❌ Error conectando PostgreSQL:', err);
  }
  
  // Mantener el proceso activo
  console.log('🔄 Servidor listo para recibir peticiones...');
});

// Manejar cierre graceful
process.on('SIGINT', () => {
  console.log('\n\n🛑 Cerrando servidor...');
  server.close(async () => {
    console.log('✅ Servidor HTTP cerrado');
    await sql.end({ timeout: 5 });
    console.log('✅ Conexión PostgreSQL cerrada');
    process.exit(0);
  });
});

server.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    console.error(`❌ Puerto ${PORT} ya está en uso`);
  } else {
    console.error('❌ Error del servidor:', error);
  }
  process.exit(1);
});

process.on('uncaughtException', (error) => {
  console.error('❌ Excepción no capturada:', error);
  console.error('Stack:', error.stack);
  // NO terminar el proceso para debugging
  // process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Promesa rechazada no manejada:', reason);
  console.error('Promise:', promise);
  // NO terminar el proceso para debugging
  // process.exit(1);
});