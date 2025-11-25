
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

app.listen(PORT, '0.0.0.0', async () => {
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
});