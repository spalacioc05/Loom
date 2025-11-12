# TTS Gratuito Implementado ✅

## ¿Qué cambió?

Se implementó un sistema de TTS **completamente gratuito** usando Google Translate TTS como alternativa a Azure Speech (que tiene cuota limitada).

## Archivos creados/modificados

### Nuevos archivos:
- `backend/services/free_tts.js` - Motor TTS gratuito usando google-tts-api
- `backend/services/tts_provider.js` - Selector automático entre Azure y Free TTS
- `backend/generate_batch_audios.js` - Script para generar múltiples audios de un libro

### Archivos modificados:
- `backend/controllers/tts_controllers.js` - Ahora usa tts_provider en lugar de azure_tts
- `backend/test_force_tts.js` - Actualizado para usar tts_provider
- `backend/.env` - Agregadas variables TTS_PROVIDER y MOCK_TTS

## Configuración

En `backend/.env`:

```env
TTS_PROVIDER=free        # Fuerza uso de Google TTS (gratuito)
MOCK_TTS=false          # Desactiva modo de prueba
```

### Opciones para TTS_PROVIDER:
- `free` - Usa Google Translate TTS (gratuito, ilimitado*)
- `azure` - Usa Azure Speech (requiere cuota)
- *(dejar vacío)* - Auto-selección: usa Azure si hay credenciales, si no usa free

*Nota: Google puede limitar temporalmente si haces demasiadas requests muy rápido. El script batch tiene delay de 1s entre audios.

## Cómo usar

### 1. Generar audios para un libro

```powershell
# En carpeta backend
$env:MOCK_TTS="false"
$env:TTS_PROVIDER="free"

# Generar 10 audios del libro 2
node generate_batch_audios.js 2 10

# Generar 20 audios del libro 1
node generate_batch_audios.js 1 20
```

### 2. Ver estado de audios

```powershell
node diagnose_tts_status.js 1 2 3
```

### 3. Generar un solo audio (para pruebas)

```powershell
$env:MOCK_TTS="false"
$env:TTS_PROVIDER="free"
node test_force_tts.js 2
```

## Iniciar backend con Free TTS

Asegúrate que tu `.env` tenga:
```env
TTS_PROVIDER=free
MOCK_TTS=false
```

Luego:
```powershell
npm run dev
```

El backend automáticamente usará Google TTS para todas las generaciones.

## Funcionamiento

1. **Subir libro**: La segmentación funciona igual (divide PDF en chunks).
2. **Reproducir**: Al dar play, el frontend llama a `/tts/libro/:id/audios?autoGenerate=5`
3. **Generación on-demand**: El backend genera los primeros 5 audios faltantes usando Google TTS.
4. **Polling**: El frontend refresca cada 3-10s para obtener nuevos audios generados.
5. **Reproducción progresiva**: Empieza a reproducir tan pronto hay 1 audio disponible.

## Calidad del audio

- **Azure TTS**: Voces neuronales de alta calidad, selección por región/género.
- **Google TTS**: Voz estándar de Google Translate, solo español genérico.
- Ambos generan MP3 válido que el reproductor puede leer.

## Limitaciones de Free TTS

- No se pueden seleccionar voces específicas (siempre usa voz española de Google).
- Velocidad fija (no respeta el parámetro `rate` del frontend).
- Google puede rate-limitar si generas > 50 audios/minuto (usa batch script con delay).

## Ventajas de Free TTS

- ✅ **Completamente gratuito**
- ✅ **Sin cuotas mensuales**
- ✅ **Funciona de inmediato**
- ✅ **No requiere configuración adicional**
- ✅ **Genera audios de calidad aceptable**

## Migración a Azure (opcional)

Si más adelante quieres volver a Azure:

1. Actualiza credenciales en `.env`:
   ```env
   AZURE_SPEECH_KEY=tu_nueva_key
   AZURE_SPEECH_REGION=westus
   TTS_PROVIDER=azure
   ```

2. Reinicia backend.

3. Los nuevos audios se generarán con Azure TTS de alta calidad.

## Troubleshooting

**Error: "Cannot find module 'google-tts-api'"**
```powershell
npm install google-tts-api
```

**Audios no se generan**
- Verifica que MOCK_TTS=false en .env
- Verifica que TTS_PROVIDER=free en .env
- Reinicia el backend después de cambiar .env

**Rate limiting de Google**
- Reduce el número de audios generados simultáneamente
- Aumenta el delay en generate_batch_audios.js (línea del setTimeout)

## Scripts útiles

```powershell
# Diagnosticar estado de libros
node diagnose_tts_status.js 1 2 3

# Generar batch de audios
node generate_batch_audios.js <libro_id> <cantidad>

# Forzar generación de 1 audio
node test_force_tts.js <libro_id>

# Verificar bucket de Storage
node test_storage_audios.js
```

## Estado actual

✅ Libro 2: 18 audios generados (segmentos 1-13 + algunos extras)
✅ Storage: bucket audios_tts funcionando
✅ Backend: TTS provider configurado
✅ Frontend: Compatible con nueva implementación

¡La app ya puede leer libros usando TTS gratuito! 🎉
