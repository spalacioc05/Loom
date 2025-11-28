import Redis from 'ioredis';

class RedisCache {
  constructor() {
    this.client = null;
    this.isConnected = false;
    this.initialize();
  }

  async initialize() {
    try {
      // Verificar si Redis está habilitado
      const redisHost = process.env.REDIS_HOST;
      const redisUrl = process.env.REDIS_URL;
      
      if (!redisHost && !redisUrl) {
        console.log('[Redis Cache] ℹ️  Redis no configurado - Continuando sin cache (modo degradado)');
        this.isConnected = false;
        return;
      }
      
      // Soportar REDIS_URL para Render o configuración local
      if (redisUrl) {
        // Producción: usar REDIS_URL de Render
        console.log('[Redis Cache] 🌐 Conectando con REDIS_URL...');
        this.client = new Redis(redisUrl, {
          maxRetriesPerRequest: 3,
          enableReadyCheck: true,
          retryStrategy: (times) => {
            if (times > 3) {
              console.warn('[Redis Cache] ⚠️ Desconectando después de 3 intentos fallidos');
              return null;
            }
            return Math.min(times * 200, 2000);
          },
          // TLS para Render Redis
          tls: process.env.NODE_ENV === 'production' ? {
            rejectUnauthorized: false
          } : undefined,
        });
      } else {
        // Desarrollo: configuración local
        console.log('[Redis Cache] 🏠 Conectando a Redis local...');
        this.client = new Redis({
          host: process.env.REDIS_HOST || 'localhost',
          port: parseInt(process.env.REDIS_PORT || '6379', 10),
          password: process.env.REDIS_PASSWORD,
          db: 0,
          retryStrategy: (times) => {
            if (times > 3) {
              console.warn('[Redis Cache] ⚠️ Desconectando después de 3 intentos fallidos');
              return null;
            }
            return Math.min(times * 200, 2000);
          },
          maxRetriesPerRequest: 3,
          enableReadyCheck: true,
          lazyConnect: false,
        });
      }

      this.client.on('connect', () => {
        console.log('[Redis Cache] 🔗 Conectando...');
      });

      this.client.on('ready', () => {
        this.isConnected = true;
        console.log('[Redis Cache] ✅ Listo y operacional');
      });

      this.client.on('error', (err) => {
        this.isConnected = false;
        console.error('[Redis Cache] ❌ Error:', err.message);
      });

      this.client.on('close', () => {
        this.isConnected = false;
        console.log('[Redis Cache] 🔌 Conexión cerrada');
      });

      // Esperar a que esté listo
      await this.client.ping();
      console.log('[Redis Cache] 📡 Ping exitoso');
    } catch (error) {
      console.warn('[Redis Cache] ⚠️ No se pudo conectar a Redis:', error.message);
      console.warn('[Redis Cache] ℹ️ Continuando sin cache (modo degradado)');
      this.isConnected = false;
    }
  }

  // ============================================
  // CACHE DE AUDIOS GENERADOS
  // ============================================

  /**
   * Cachea la URL de un audio generado
   * Key: audio:{documentId}:{voiceId}:{segmentNum}
   * TTL: 7 días (los audios no cambian una vez generados)
   */
  async cacheAudioUrl(documentId, voiceId, segmentNum, audioUrl, audioId) {
    if (!this.isConnected) return false;

    try {
      const key = `audio:${documentId}:${voiceId}:${segmentNum}`;
      const value = JSON.stringify({
        audioUrl,
        audioId,
        cachedAt: new Date().toISOString(),
      });

      await this.client.setex(key, 60 * 60 * 24 * 7, value); // 7 días
      console.log(`[Redis Cache] 💾 Audio cacheado: ${key}`);
      return true;
    } catch (error) {
      console.error('[Redis Cache] Error al cachear audio:', error.message);
      return false;
    }
  }

  /**
   * Obtiene un audio cacheado
   */
  async getAudioUrl(documentId, voiceId, segmentNum) {
    if (!this.isConnected) return null;

    try {
      const key = `audio:${documentId}:${voiceId}:${segmentNum}`;
      const cached = await this.client.get(key);

      if (cached) {
        console.log(`[Redis Cache] ✅ Audio encontrado en cache: ${key}`);
        return JSON.parse(cached);
      }

      return null;
    } catch (error) {
      console.error('[Redis Cache] Error al obtener audio:', error.message);
      return null;
    }
  }

  /**
   * Cachea múltiples audios de un libro (batch)
   */
  async cacheBookAudios(documentId, voiceId, audios) {
    if (!this.isConnected) return false;

    try {
      const pipeline = this.client.pipeline();
      
      for (const audio of audios) {
        const key = `audio:${documentId}:${voiceId}:${audio.segmentNum}`;
        const value = JSON.stringify({
          audioUrl: audio.audioUrl,
          audioId: audio.audioId,
          cachedAt: new Date().toISOString(),
        });
        pipeline.setex(key, 60 * 60 * 24 * 7, value);
      }

      await pipeline.exec();
      console.log(`[Redis Cache] 💾 Batch de ${audios.length} audios cacheados para documento ${documentId}`);
      return true;
    } catch (error) {
      console.error('[Redis Cache] Error al cachear batch de audios:', error.message);
      return false;
    }
  }

  // ============================================
  // CACHE DE PROGRESO DE USUARIO
  // ============================================

  /**
   * Cachea el progreso de lectura de un usuario
   * Key: progress:{userId}:{documentId}
   * TTL: 1 hora (se sincroniza periódicamente con BD)
   */
  async cacheUserProgress(userId, documentId, progressData) {
    if (!this.isConnected) return false;

    try {
      const key = `progress:${userId}:${documentId}`;
      const value = JSON.stringify({
        ...progressData,
        updatedAt: new Date().toISOString(),
      });

      await this.client.setex(key, 60 * 60, value); // 1 hora
      return true;
    } catch (error) {
      console.error('[Redis Cache] Error al cachear progreso:', error.message);
      return false;
    }
  }

  /**
   * Obtiene el progreso cacheado de un usuario
   */
  async getUserProgress(userId, documentId) {
    if (!this.isConnected) return null;

    try {
      const key = `progress:${userId}:${documentId}`;
      const cached = await this.client.get(key);

      if (cached) {
        return JSON.parse(cached);
      }

      return null;
    } catch (error) {
      console.error('[Redis Cache] Error al obtener progreso:', error.message);
      return null;
    }
  }

  // ============================================
  // CACHE DE METADATA DE LIBROS
  // ============================================

  /**
   * Cachea información de un libro
   * Key: book:{bookId}
   * TTL: 1 día
   */
  async cacheBookMetadata(bookId, bookData) {
    if (!this.isConnected) return false;

    try {
      const key = `book:${bookId}`;
      const value = JSON.stringify({
        ...bookData,
        cachedAt: new Date().toISOString(),
      });

      await this.client.setex(key, 60 * 60 * 24, value); // 1 día
      return true;
    } catch (error) {
      console.error('[Redis Cache] Error al cachear metadata de libro:', error.message);
      return false;
    }
  }

  /**
   * Obtiene metadata de libro cacheada
   */
  async getBookMetadata(bookId) {
    if (!this.isConnected) return null;

    try {
      const key = `book:${bookId}`;
      const cached = await this.client.get(key);

      if (cached) {
        console.log(`[Redis Cache] ✅ Metadata de libro encontrada: ${bookId}`);
        return JSON.parse(cached);
      }

      return null;
    } catch (error) {
      console.error('[Redis Cache] Error al obtener metadata de libro:', error.message);
      return null;
    }
  }

  // ============================================
  // CACHE DE LISTA DE AUDIOS DE LIBRO
  // ============================================

  /**
   * Cachea la lista completa de audios de un libro
   * Key: book_audios:{bookId}:{voiceId}
   * TTL: 1 hora
   */
  async cacheBookAudiosList(bookId, voiceId, audiosList) {
    if (!this.isConnected) return false;

    try {
      const key = `book_audios:${bookId}:${voiceId}`;
      const value = JSON.stringify({
        audios: audiosList,
        cachedAt: new Date().toISOString(),
        count: audiosList.length,
      });

      await this.client.setex(key, 60 * 60, value); // 1 hora
      console.log(`[Redis Cache] 💾 Lista de audios cacheada: ${key} (${audiosList.length} audios)`);
      return true;
    } catch (error) {
      console.error('[Redis Cache] Error al cachear lista de audios:', error.message);
      return false;
    }
  }

  /**
   * Obtiene la lista de audios cacheada
   */
  async getBookAudiosList(bookId, voiceId) {
    if (!this.isConnected) return null;

    try {
      const key = `book_audios:${bookId}:${voiceId}`;
      const cached = await this.client.get(key);

      if (cached) {
        const data = JSON.parse(cached);
        console.log(`[Redis Cache] ✅ Lista de audios encontrada: ${key} (${data.count} audios)`);
        return data.audios;
      }

      return null;
    } catch (error) {
      console.error('[Redis Cache] Error al obtener lista de audios:', error.message);
      return null;
    }
  }

  // ============================================
  // INVALIDACIÓN DE CACHE
  // ============================================

  /**
   * Invalida cache de audios de un libro
   */
  async invalidateBookAudios(bookId, voiceId = '*') {
    if (!this.isConnected) return false;

    try {
      const pattern = voiceId === '*' 
        ? `book_audios:${bookId}:*`
        : `book_audios:${bookId}:${voiceId}`;
      
      const keys = await this.client.keys(pattern);
      if (keys.length > 0) {
        await this.client.del(...keys);
        console.log(`[Redis Cache] 🗑️ Invalidados ${keys.length} caches de audios para libro ${bookId}`);
      }
      return true;
    } catch (error) {
      console.error('[Redis Cache] Error al invalidar cache:', error.message);
      return false;
    }
  }

  /**
   * Invalida la cache de la lista de voces (`voices:all`).
   */
  async invalidateVoicesCache() {
    if (!this.isConnected) return false;

    try {
      const key = 'voices:all';
      const exists = await this.client.exists(key);
      if (exists) {
        await this.client.del(key);
        console.log('[Redis Cache] 🗑️ Cache de voces invalidada');
      } else {
        console.log('[Redis Cache] ℹ️ No existía cache de voces');
      }
      return true;
    } catch (error) {
      console.error('[Redis Cache] Error invalidando cache de voces:', error.message);
      return false;
    }
  }

  // ============================================
  // UTILIDADES
  // ============================================

  /**
   * Obtiene estadísticas del cache
   */
  async getStats() {
    if (!this.isConnected) return { connected: false };

    try {
      const info = await this.client.info('stats');
      const dbSize = await this.client.dbsize();
      
      return {
        connected: true,
        dbSize,
        info: this.parseInfo(info),
      };
    } catch (error) {
      console.error('[Redis Cache] Error al obtener stats:', error.message);
      return { connected: false, error: error.message };
    }
  }

  parseInfo(infoString) {
    const lines = infoString.split('\r\n');
    const stats = {};
    
    for (const line of lines) {
      if (line && !line.startsWith('#') && line.includes(':')) {
        const [key, value] = line.split(':');
        stats[key] = value;
      }
    }
    
    return stats;
  }

  /**
   * Cierra la conexión de Redis
   */
  async close() {
    if (this.client) {
      await this.client.quit();
      console.log('[Redis Cache] 👋 Conexión cerrada');
    }
  }
}

// Exportar instancia singleton
export default new RedisCache();
