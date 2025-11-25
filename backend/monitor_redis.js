import Redis from 'ioredis';

const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379', 10),
});

console.log('🔍 Monitoreando Redis Cache...\n');

async function showStats() {
  try {
    const keys = await redis.keys('*');
    console.clear();
    console.log('═══════════════════════════════════════════════════════');
    console.log('  🗄️  REDIS CACHE MONITOR');
    console.log('═══════════════════════════════════════════════════════\n');
    console.log(`📊 Total keys: ${keys.length}\n`);
    
    if (keys.length > 0) {
      console.log('🔑 Keys almacenadas:\n');
      for (const key of keys) {
        const ttl = await redis.ttl(key);
        const type = await redis.type(key);
        const size = await redis.strlen(key);
        
        const ttlStr = ttl > 0 ? `${Math.floor(ttl / 60)}m ${ttl % 60}s` : 'sin expiración';
        console.log(`  • ${key}`);
        console.log(`    Tipo: ${type} | TTL: ${ttlStr} | Tamaño: ${size} bytes`);
        
        // Mostrar preview del contenido si es string pequeño
        if (type === 'string' && size < 500) {
          const value = await redis.get(key);
          try {
            const parsed = JSON.parse(value);
            if (key.startsWith('voices:')) {
              console.log(`    Contenido: ${parsed.length} voces`);
            } else if (key.startsWith('book_audios:')) {
              console.log(`    Contenido: ${parsed.audios?.length || 0} audios, cacheado: ${parsed.cachedAt}`);
            }
          } catch {
            console.log(`    Preview: ${value.substring(0, 100)}...`);
          }
        }
        console.log();
      }
    } else {
      console.log('⚠️  Cache vacío - ninguna key almacenada aún\n');
    }
    
    const info = await redis.info('stats');
    const lines = info.split('\r\n');
    const stats = {};
    for (const line of lines) {
      if (line && !line.startsWith('#') && line.includes(':')) {
        const [key, value] = line.split(':');
        stats[key] = value;
      }
    }
    
    console.log('📈 Estadísticas:');
    console.log(`  • Comandos ejecutados: ${stats.total_commands_processed || 'N/A'}`);
    console.log(`  • Conexiones recibidas: ${stats.total_connections_received || 'N/A'}`);
    console.log(`  • Hits/Misses: ${stats.keyspace_hits || 0} / ${stats.keyspace_misses || 0}`);
    
    const memory = await redis.info('memory');
    const memLines = memory.split('\r\n');
    for (const line of memLines) {
      if (line.startsWith('used_memory_human:')) {
        console.log(`  • Memoria usada: ${line.split(':')[1]}`);
      }
    }
    
    console.log('\n═══════════════════════════════════════════════════════');
    console.log('  Actualizando cada 5 segundos... (Ctrl+C para salir)');
    console.log('═══════════════════════════════════════════════════════\n');
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

// Actualizar cada 5 segundos
showStats();
setInterval(showStats, 5000);

// Manejar Ctrl+C
process.on('SIGINT', async () => {
  console.log('\n\n👋 Cerrando monitor...');
  await redis.quit();
  process.exit(0);
});
