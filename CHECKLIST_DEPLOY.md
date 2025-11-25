# ✅ CHECKLIST DE DESPLIEGUE

Sigue estos pasos EN ORDEN. Marca cada uno cuando lo completes.

---

## 📦 FASE 1: PREPARACIÓN LOCAL

### [ ] 1.1 Verificar archivos creados
```bash
# Verifica que estos archivos existan:
- render.yaml (en raíz del proyecto)
- DEPLOY_RENDER.md (guía detallada)
- backend/services/redis_cache.js (actualizado para producción)
- frontend/lib/services/api_service.dart (soporta prod/dev)
```

### [ ] 1.2 Hacer commit de cambios
```bash
cd C:\Users\sarai\OneDrive\Desktop\Servicio
git add .
git commit -m "feat: Configuración Render + Redis cache"
git push origin main
```

**IMPORTANTE:** Espera a que el push termine antes de continuar.

---

## 🌐 FASE 2: CONFIGURAR RENDER

### [ ] 2.1 Crear cuenta en Render
1. Ve a: https://render.com
2. Click "Get Started"
3. Elige "Sign up with GitHub"
4. Autoriza Render a acceder a tus repos

### [ ] 2.2 Crear servicios con Blueprint
1. En Dashboard, click **"New +"**
2. Selecciona **"Blueprint"**
3. Click **"Connect a repository"**
4. Busca y selecciona: **Loom**
5. Render mostrará:
   ```
   ✓ loom-backend (Web Service)
   ✓ loom-redis (Redis)
   ```
6. Click **"Apply"**
7. Espera ~3 minutos a que se creen ambos servicios

---

## 🔑 FASE 3: CONFIGURAR VARIABLES DE ENTORNO

### [ ] 3.1 Obtener credenciales de Supabase

#### Database URL:
1. Ve a: https://supabase.com/dashboard/project/yditubxizgubcntiysnh/settings/database
2. Copia "Connection string" en modo **Session**
3. Reemplaza `[YOUR-PASSWORD]` con tu contraseña real

#### API Keys:
1. Ve a: https://supabase.com/dashboard/project/yditubxizgubcntiysnh/settings/api
2. Copia:
   - Project URL
   - anon public
   - service_role secret

### [ ] 3.2 Configurar en Render

1. En Render Dashboard, click en **loom-backend**
2. Ve a pestaña **"Environment"**
3. Click **"Add Environment Variable"** y agrega:

```
Name: DATABASE_URL
Value: [TU CONNECTION STRING DE SUPABASE]
```

```
Name: SUPABASE_URL  
Value: https://yditubxizgubcntiysnh.supabase.co
```

```
Name: SUPABASE_ANON_KEY
Value: [TU ANON KEY]
```

```
Name: SUPABASE_SERVICE_ROLE_KEY
Value: [TU SERVICE ROLE KEY]
```

4. Click **"Save Changes"**

**NOTA:** El backend se reiniciará automáticamente.

---

## ✅ FASE 4: VERIFICAR DESPLIEGUE

### [ ] 4.1 Revisar logs
1. En Render Dashboard → **loom-backend** → **Logs**
2. Espera a ver estas líneas (tarda ~5 minutos):
   ```
   ✓ Build succeeded
   [Redis Cache] ✅ Listo y operacional
   🚀 Backend corriendo en puerto 10000
   ✅ PostgreSQL conectado!
   ```

### [ ] 4.2 Copiar URL del backend
1. En **loom-backend** → **Settings**
2. Copia la URL (ejemplo: `https://loom-backend-xxxx.onrender.com`)
3. **GUÁRDALA**, la necesitarás para el frontend

### [ ] 4.3 Probar health check
1. Abre en navegador: `https://loom-backend-xxxx.onrender.com/health`
2. Deberías ver JSON con:
   ```json
   {
     "ok": true,
     "checks": {
       "postgres_primary": { "ok": true },
       "redis_cache": { "connected": true }
     }
   }
   ```

### [ ] 4.4 Probar endpoint de voces
1. Abre: `https://loom-backend-xxxx.onrender.com/voices`
2. Deberías ver array con 4 voces

---

## 📱 FASE 5: ACTUALIZAR FRONTEND

### [ ] 5.1 Actualizar URL de producción

1. Abre: `frontend/lib/services/api_service.dart`
2. Busca la línea:
   ```dart
   const production = 'https://loom-backend.onrender.com';
   ```
3. Reemplaza con TU URL real de Render:
   ```dart
   const production = 'https://loom-backend-xxxx.onrender.com';
   ```

### [ ] 5.2 Hacer commit
```bash
cd C:\Users\sarai\OneDrive\Desktop\Servicio
git add frontend/lib/services/api_service.dart
git commit -m "feat: URL de producción en Render"
git push origin main
```

### [ ] 5.3 Compilar app para testing
```bash
cd frontend
flutter build apk --debug
```

### [ ] 5.4 Probar app en debug
1. Instala la APK en tu celular
2. Abre la app
3. Revisa logs para confirmar que usa URL local:
   ```
   🏠 Modo DESARROLLO - usando: http://172.23.32.1:3000
   ```

### [ ] 5.5 Compilar app para release
```bash
flutter build apk --release
```

### [ ] 5.6 Probar app en release
1. Instala la APK de release
2. Abre la app
3. Revisa logs para confirmar que usa Render:
   ```
   🚀 Modo PRODUCCIÓN - usando: https://loom-backend-xxxx.onrender.com
   ```

---

## 🎉 FASE 6: VERIFICACIÓN FINAL

### [ ] 6.1 Verificar Redis en producción
1. En Render Dashboard → **loom-redis** → **Metrics**
2. Deberías ver:
   - Memory usage aumentando
   - Commands/sec > 0

### [ ] 6.2 Verificar cache funcionando
1. Abre la app (release mode)
2. Carga un libro
3. En Render logs verás:
   ```
   [Voices] 📊 Cache miss - consultando PostgreSQL...
   💾 [Redis Cache] Voces cacheadas
   ```
4. Cierra y reabre la app
5. En logs verás:
   ```
   🚀 [Redis Cache] ✅ Voces respondidas desde CACHE
   ```

### [ ] 6.3 Probar reproducción de audios
1. Abre un libro
2. Genera audios
3. Reproduce
4. Verifica que se escuche correctamente

---

## 🔥 TROUBLESHOOTING

### ❌ Error: "Build failed"
```bash
# Ver logs detallados
# En Render Dashboard → loom-backend → Logs

# Solución común: verificar package.json
cd backend
npm install  # Probar localmente
git add .
git commit -m "fix: dependencias"
git push
```

### ❌ Error: "Redis connection refused"
1. Verifica que `loom-redis` esté "Available"
2. En `loom-backend` → Environment, `REDIS_URL` debe estar autoconfigurada
3. Si no está, elimina ambos servicios y vuelve a aplicar Blueprint

### ❌ Error: "Database connection failed"
1. Verifica `DATABASE_URL` en Environment
2. Prueba conexión desde local:
   ```bash
   cd backend
   node -e "require('dotenv').config(); console.log(process.env.DATABASE_URL)"
   ```

### ❌ App carga pero no hay libros
1. Verifica que Supabase tenga datos en `tbl_libros`
2. Verifica CORS en backend (ya configurado con `origin: '*'`)
3. Revisa logs de Render para ver errores

---

## 📊 MONITOREO CONTINUO

### Render Dashboard
- **Logs**: Tiempo real
- **Metrics**: CPU, Memory, Latency
- **Events**: Deploys, crashes

### Desde Terminal (opcional)
```bash
# Instalar Render CLI
npm install -g render-cli

# Ver logs en tiempo real
render logs -s loom-backend --tail
```

---

## 💰 COSTOS

### Free Tier Incluye:
- ✅ 750 horas/mes de Web Service (suficiente 24/7)
- ✅ 25 MB de Redis
- ✅ SSL/TLS automático
- ✅ Builds ilimitados

### Limitaciones:
- ⚠️ Sleep después de 15 min inactividad (cold start ~30s)
- ⚠️ Redis limitado a 25 MB
- ⚠️ Sin soporte prioritario

### Upgrade ($7/mes):
- ✅ Sin sleep (always on)
- ✅ Más memoria/CPU
- ✅ Soporte prioritario

---

¿Algún paso no funcionó? Revisa DEPLOY_RENDER.md para detalles.
