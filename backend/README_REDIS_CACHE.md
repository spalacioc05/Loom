# Redis Cache para Audios TTS

## 📦 Instalación de Redis

### Windows

1. **Descargar Redis para Windows:**
   - Ir a: https://github.com/microsoftarchive/redis/releases
   - Descargar: `Redis-x64-3.0.504.msi` o versión más reciente
   - Instalar ejecutando el .msi

2. **O usar Docker (recomendado):**
   ```powershell
   docker run -d --name redis-loom -p 6379:6379 redis:latest
   ```

3. **O usar Windows Subsystem for Linux (WSL):**
   ```bash
   sudo apt update
   sudo apt install redis-server
   sudo service redis-server start
   ```

### Verificar que Redis está corriendo

```powershell
# Si instalaste con .msi
redis-cli ping
# Debe responder: PONG

# Si usaste Docker
docker exec -it redis-loom redis-cli ping
```

## 🚀 Configuración

Redis ya está configurado en el proyecto. Solo necesitas:

1. **Asegurarte de que Redis esté corriendo** en `localhost:6379`

2. **Variables de entorno** (opcional, ya tienen valores por defecto):
   ```env
   REDIS_HOST=localhost
   REDIS_PORT=6379
   REDIS_PASSWORD=
   ```

## ⚡ Beneficios del Cache

### 1. **Audios cacheados por 7 días**
- Una vez generado un audio, se guarda en Redis
- Próximas requests devuelven el audio instantáneamente
- No se regenera el mismo audio dos veces

### 2. **Listas de audios cacheadas por 1 hora**
- Consultas a `/tts/libro/:id/audios` son ultra rápidas
- Se invalida automáticamente cuando se generan nuevos audios

### 3. **Progreso de usuario en memoria**
- Actualizaciones de progreso se guardan primero en Redis
- Se sincronizan con PostgreSQL periódicamente
- Lectura/escritura 10x más rápida

### 4. **Metadata de libros cacheada por 1 día**
- Información de libros se carga una sola vez
- Reduce carga en PostgreSQL

## 📊 Monitoreo

### Ver estadísticas del cache

```bash
GET /health
```

Respuesta incluirá:
```json
{
  "checks": {
    "redis_cache": {
      "connected": true,
      "dbSize": 42,
      "info": {
        "total_connections_received": "100",
        "total_commands_processed": "523",
        "used_memory_human": "2.5M"
      }
    }
  }
}
```

### Monitorear Redis directamente

```bash
# Conectarse a Redis CLI
redis-cli

# Ver todas las keys
KEYS *

# Ver una key específica
GET audio:doc-123:voice-456:1

# Ver stats
INFO stats

# Ver memoria usada
INFO memory

# Limpiar TODO el cache (cuidado!)
FLUSHALL
```

## 🔑 Estructura de Keys en Redis

### Audios
```
audio:{documentId}:{voiceId}:{segmentNum}
Ejemplo: audio:uuid-123:voice-es-mx:5
TTL: 7 días
Valor: { "audioUrl": "https://...", "audioId": 42, "cachedAt": "2025-..." }
```

### Listas de audios
```
book_audios:{bookId}:{voiceId}
Ejemplo: book_audios:15:voice-es-mx
TTL: 1 hora
Valor: { "audios": [...], "count": 25, "cachedAt": "..." }
```

### Progreso de usuario
```
progress:{userId}:{documentId}
Ejemplo: progress:user-123:doc-456
TTL: 1 hora
Valor: { "voice_id": "...", "segment_id": 5, "intra_ms": 1500 }
```

### Metadata de libros
```
book:{bookId}
Ejemplo: book:42
TTL: 1 día
Valor: { "titulo": "...", "autor": "...", ... }
```

## 🛠️ Invalidación de Cache

El cache se invalida automáticamente cuando:

1. **Se generan nuevos audios** → Invalida `book_audios:{bookId}:*`
2. **Se edita un libro** → Invalida `book:{bookId}`
3. **Se cambia progreso** → Actualiza cache de progreso

### Invalidar manualmente desde código

```javascript
import redisCache from './services/redis_cache.js';

// Invalidar audios de un libro
await redisCache.invalidateBookAudios(bookId);

// Invalidar metadata
await redisCache.client.del(`book:${bookId}`);
```

## 📈 Rendimiento Esperado

### Sin Redis (antes)
- Primera carga de libro: **5-10 segundos**
- Cargas subsecuentes: **3-5 segundos**
- Generación de audio: **2-4 segundos por segmento**

### Con Redis (ahora)
- Primera carga de libro: **5-10 segundos** (igual, debe generar)
- Cargas subsecuentes: **< 100ms** ⚡
- Audio ya generado: **< 50ms** ⚡
- Actualización de progreso: **< 20ms** ⚡

## 🐛 Troubleshooting

### "Redis no está conectado"
```
[Redis Cache] ⚠️ No se pudo conectar a Redis: connect ECONNREFUSED
```
**Solución:**
1. Verificar que Redis esté corriendo: `redis-cli ping`
2. Si usas Docker: `docker ps` y verificar que el contenedor esté activo
3. Revisar variables de entorno REDIS_HOST y REDIS_PORT

### El cache no funciona pero la app sí
La app funciona en "modo degradado" sin Redis. Todo seguirá funcionando pero más lento.

### Limpiar cache corrupto
```bash
redis-cli FLUSHALL
```

### Ver logs de Redis
```bash
# Docker
docker logs redis-loom

# WSL
sudo journalctl -u redis-server
```

## 🎯 Próximas Mejoras

1. **Pre-generación inteligente:**
   - Detectar qué libros son más populares
   - Pre-generar audios antes de que el usuario los pida

2. **Cache compartido entre usuarios:**
   - Si dos usuarios escuchan el mismo libro/voz
   - Solo se genera una vez, ambos lo aprovechan

3. **Compresión de metadata:**
   - Reducir tamaño de valores en Redis
   - Aumentar capacidad de cache

4. **Clustering de Redis:**
   - Para escalar horizontalmente
   - Mayor disponibilidad

## 📝 Comandos Útiles

```bash
# Iniciar Redis (Windows con instalador)
redis-server

# Iniciar Redis (Docker)
docker start redis-loom

# Detener Redis (Docker)
docker stop redis-loom

# Monitorear en tiempo real
redis-cli MONITOR

# Ver tamaño de base de datos
redis-cli DBSIZE

# Obtener info de memoria
redis-cli INFO memory

# Ver keys por patrón
redis-cli KEYS "audio:*"
redis-cli KEYS "progress:*"
```
