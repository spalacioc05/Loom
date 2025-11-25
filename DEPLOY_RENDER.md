# 🚀 Despliegue en Render - Guía Paso a Paso

## 📋 Requisitos Previos

- [ ] Cuenta en Render.com (https://render.com)
- [ ] Cuenta en GitHub
- [ ] Base de datos PostgreSQL en Supabase
- [ ] Código subido a GitHub

---

## PASO 1: Subir Código a GitHub

```bash
# 1. Verifica que estás en el directorio raíz del proyecto
cd C:\Users\sarai\OneDrive\Desktop\Servicio

# 2. Agrega todos los cambios
git add .

# 3. Haz commit
git commit -m "feat: Configuración para Render con Redis cache"

# 4. Sube a GitHub
git push origin main
```

---

## PASO 2: Crear Servicios en Render

### 2.1 Acceder a Render

1. Ve a: https://dashboard.render.com
2. Inicia sesión con tu cuenta de GitHub
3. Click en **"New +"** (esquina superior derecha)
4. Selecciona **"Blueprint"**

### 2.2 Conectar Repositorio

1. Click **"Connect a repository"**
2. Busca y selecciona tu repositorio: **Loom**
3. Render detectará automáticamente el archivo `render.yaml`
4. Verás 2 servicios listados:
   - ✅ `loom-backend` (Web Service)
   - ✅ `loom-redis` (Redis)
5. Click **"Apply"**

### 2.3 Esperar Creación

Render creará ambos servicios automáticamente. Esto toma ~2-3 minutos.

Verás:
```
Creating loom-redis... ✓
Creating loom-backend... (en progreso)
```

---

## PASO 3: Configurar Variables de Entorno

### 3.1 Obtener Credenciales de Supabase

1. Ve a: https://supabase.com/dashboard/project/yditubxizgubcntiysnh/settings/api
2. Copia:
   - **Project URL**: `SUPABASE_URL`
   - **anon public**: `SUPABASE_ANON_KEY`
   - **service_role**: `SUPABASE_SERVICE_ROLE_KEY`

3. Ve a: https://supabase.com/dashboard/project/yditubxizgubcntiysnh/settings/database
4. Copia la **Connection string** en modo "Session":
   ```
   postgresql://postgres.[PROJECT-REF]:[PASSWORD]@aws-1-us-east-1.pooler.supabase.com:5432/postgres
   ```

### 3.2 Configurar en Render

1. En Render Dashboard, click en **loom-backend**
2. Ve a la pestaña **"Environment"**
3. Click **"Add Environment Variable"**
4. Agrega una por una:

```env
DATABASE_URL=postgresql://postgres.yditubxizgubcntiysnh:[TU_PASSWORD]@aws-1-us-east-1.pooler.supabase.com:5432/postgres

SUPABASE_URL=https://yditubxizgubcntiysnh.supabase.co

SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

5. Click **"Save Changes"**

**IMPORTANTE:** Reemplaza `[TU_PASSWORD]` con tu contraseña real de Supabase.

---

## PASO 4: Verificar Despliegue

### 4.1 Revisar Logs

1. En Render Dashboard → **loom-backend** → **Logs**
2. Busca estas líneas (toma ~5 minutos la primera vez):

```
==> Cloning from https://github.com/spalacioc05/Loom...
==> Running build command 'cd backend && npm install'...
✓ Build succeeded
==> Deploying...
[Redis Cache] 🌐 Conectando con REDIS_URL...
[Redis Cache] ✅ Listo y operacional
🚀 Backend corriendo en puerto 10000
✅ PostgreSQL conectado!
```

### 4.2 Probar Health Check

1. Copia la URL de tu servicio (ejemplo: `https://loom-backend-xxxx.onrender.com`)
2. Abre en navegador:
   ```
   https://loom-backend-xxxx.onrender.com/health
   ```

3. Deberías ver:
```json
{
  "ok": true,
  "timestamp": "2025-11-25T...",
  "checks": {
    "postgres_primary": { "ok": true },
    "voices": { "ok": true, "total": 4 },
    "redis_cache": {
      "connected": true,
      "dbSize": 0
    }
  }
}
```

### 4.3 Probar Endpoint de Voces

```
https://loom-backend-xxxx.onrender.com/voices
```

Deberías ver las 4 voces (es-Normal, es-Clara, en-Normal, en-Clear).

---

## PASO 5: Actualizar Frontend

### 5.1 Modificar api_service.dart

Abre `frontend/lib/services/api_service.dart` y actualiza:

```dart
static Future<String> resolveBaseUrl() async {
  // URL de producción (Render)
  const production = 'https://loom-backend-XXXX.onrender.com';
  
  // URL de desarrollo (local)
  const development = 'http://172.23.32.1:3000';
  
  // Auto-detectar entorno
  const baseUrl = kReleaseMode ? production : development;
  
  print('🌐 Usando baseUrl: $baseUrl');
  return baseUrl;
}
```

**IMPORTANTE:** Reemplaza `XXXX` con tu ID real de Render.

### 5.2 Compilar App

```bash
cd frontend

# Para Android
flutter build apk --release

# Para iOS
flutter build ipa --release
```

---

## PASO 6: Verificar Redis Cache

### 6.1 Desde Render Dashboard

1. Click en **loom-redis**
2. Ve a **Metrics**
3. Verás gráficas de:
   - Memory Usage
   - Commands/sec
   - Connections

### 6.2 Desde la App

1. Abre la app
2. Carga un libro (primera vez)
3. Los logs del backend mostrarán:
   ```
   [Voices] 📊 Cache miss - consultando PostgreSQL...
   💾 [Redis Cache] Voces cacheadas (TTL: 24h)
   ```

4. Recarga el libro (segunda vez)
5. Los logs mostrarán:
   ```
   🚀 [Redis Cache] ✅ Voces respondidas desde CACHE (instantáneo)
   ```

---

## 🎉 ¡Despliegue Completo!

Tu backend está corriendo en Render con:
- ✅ Node.js + Express
- ✅ PostgreSQL (Supabase)
- ✅ Redis Cache (25 MB gratis)
- ✅ Free TTS
- ✅ HTTPS automático

---

## 🔧 Troubleshooting

### Error: "Redis connection refused"

**Solución:**
1. Verifica que `loom-redis` esté en estado **"Available"**
2. En `loom-backend` → Environment, verifica que `REDIS_URL` aparezca automáticamente

### Error: "Build failed"

**Solución:**
1. Revisa logs en Render Dashboard
2. Verifica que `backend/package.json` tenga todas las dependencias
3. Haz commit y push de cambios faltantes

### Error: "Database connection failed"

**Solución:**
1. Verifica que `DATABASE_URL` esté correcta
2. Asegúrate de que Supabase permita conexiones desde Render
3. Revisa que la contraseña no tenga caracteres especiales sin escapar

### App tarda en cargar (>30 segundos)

**Causa:** Cold start del Free Tier de Render (se duerme después de 15 min inactividad)

**Solución:** 
- Primera petición siempre será lenta después de inactividad
- Peticiones subsecuentes serán rápidas
- Para mantenerlo activo 24/7, considera upgrade a plan pago ($7/mes)

---

## 📊 Monitoreo Continuo

### Logs en Tiempo Real

```bash
# Desde tu terminal local
# (Requiere Render CLI: https://render.com/docs/cli)
render logs -s loom-backend --tail
```

### Métricas

En Render Dashboard → **loom-backend** → **Metrics** verás:
- CPU Usage
- Memory Usage
- Request latency
- HTTP status codes

---

¿Necesitas ayuda con algún paso específico?
