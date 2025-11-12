# Actualización de Voces - Google TTS

## Cambios Realizados

### 1. Eliminación de Metadatos/Portada en PDFs

**Archivo modificado:** `backend/workers/process_pdf.js`

- **Qué hace:** Al procesar un PDF, ahora omite los primeros 3000 caracteres que normalmente contienen metadatos, portada, índice, copyright, etc.
- **Variable configurable:** `SKIP_CHARS = 3000` (puede ajustarse según necesidad)
- **Beneficio:** Los audios empiezan directamente con el contenido del libro, sin leer información no relevante

**Ejemplo de log:**
```
Texto extraído: 125000 caracteres, 45 páginas
Omitiendo primeros 3000 caracteres (metadatos/portada)
Texto limpio: 122000 caracteres
Generados 81 segmentos
```

### 2. Voces de Google TTS (Gratuitas) - COMPLETAMENTE REEMPLAZADAS

**Archivos creados/modificados:**
- `backend/db/migrations/006_update_voices_google_tts.sql` - Nueva migración
- `backend/services/free_tts.js` - Actualizado para diferenciar voces
- `backend/apply_006_migration.js` - Script para aplicar la migración
- `backend/cleanup_azure_voices.js` - Script para eliminar voces de Azure

**Qué hace:**
1. **ELIMINA** completamente todas las voces de Azure (no solo desactiva)
2. Agrega 12 nuevas voces de Google TTS:
   - 6 voces femeninas (velocidad lenta, más clara)
   - 6 voces masculinas (velocidad normal, más rápida)

**Diferenciación entre voces:**
- ✅ **Voces Female**: Usan `slow=true` → Audio más pausado y claro (~21% más grande)
- ✅ **Voces Male**: Usan `slow=false` → Audio más rápido y dinámico
- Las variantes regionales (MX, ES, AR, CO) son solo para la UI, el acento es el mismo 'es'

**Voces disponibles:**
| Código | Idioma | Tipo | Velocidad |
|--------|--------|------|-----------|
| es-Female-1 | es | Femenina | Lenta |
| es-Female-2 | es | Femenina | Lenta |
| es-MX-Female | es-MX | Femenina | Lenta |
| es-ES-Female | es-ES | Femenina | Lenta |
| es-AR-Female | es-AR | Femenina | Lenta |
| es-CO-Female | es-CO | Femenina | Lenta |
| es-Male-1 | es | Masculina | Normal |
| es-Male-2 | es | Masculina | Normal |
| es-MX-Male | es-MX | Masculina | Normal |
| es-ES-Male | es-ES | Masculina | Normal |
| es-AR-Male | es-AR | Masculina | Normal |
| es-CO-Male | es-CO | Masculina | Normal |

### 3. Frontend - Selector de Voces

**Sin cambios necesarios:** El selector de voces en `frontend/lib/screens/book_player_screen.dart` ya funciona con el sistema de voces dinámico. Automáticamente mostrará las nuevas voces de Google TTS cuando se aplique la migración.

## Instrucciones de Uso

### ✅ YA APLICADO - Voces actualizadas

Las voces de Google TTS ya están activas y las de Azure eliminadas.

Para verificar:

```bash
cd backend
node cleanup_azure_voices.js
```

**Estado actual:**
- ✅ 12 voces de Google TTS activas
- ✅ 0 voces de Azure (completamente eliminadas)
- ✅ Diferenciación: Female (lenta) vs Male (normal)

### Procesar un nuevo libro (sin metadatos):

```bash
cd backend
node workers/process_pdf.js <libro_id>
```

Los primeros 3000 caracteres serán omitidos automáticamente.

### Generar audios con nuevas voces:

```bash
# Generar primeros 3 segmentos para todos los libros
node generate_first_audios_all_books.js

# O generar para un libro específico
node generate_batch_audios.js <libro_id> <cantidad>
```

### Cambiar voces en el frontend:

1. Abrir un libro en el reproductor
2. Tocar el chip de voz (actualmente muestra la voz seleccionada)
3. Seleccionar una nueva voz de la lista
4. Los audios se regenerarán automáticamente con la nueva voz

## Limitaciones de Google TTS

- **Sin diferenciación de acentos:** Todas las variantes (MX, ES, AR, CO) usan el mismo motor de síntesis
- **✅ SÍ hay diferencia entre voces:** Female (lenta/clara) vs Male (normal/rápida)
- **Calidad limitada:** La calidad es inferior a Azure Neural Voices pero es GRATUITA e ILIMITADA
- **Sin personalización avanzada:** No soporta estilos emocionales o pitch fino

## Posibles Mejoras Futuras

1. **Migrar a otro proveedor gratuito con más opciones:**
   - ElevenLabs (tiene plan gratuito limitado)
   - PlayHT (voces más naturales)
   - Coqui TTS (código abierto, self-hosted)
   - Piper TTS (local, offline, muy rápido)

2. **Procesamiento de audio:**
   - Agregar efectos de pitch/speed para simular diferentes voces
   - Normalización de volumen
   - Mejora de calidad con filtros

3. **Detección inteligente de metadatos:**
   - En lugar de saltar caracteres fijos, detectar primer capítulo o párrafo largo
   - Análisis de estructura del PDF (TOC, headings)
   - Configuración por libro (algunos no tienen portada extensa)

## Reversión (si es necesaria)

Si necesitas volver a las voces de Azure:

```sql
-- Reactivar voces de Azure
UPDATE tbl_voces SET activo = true WHERE proveedor = 'azure';

-- Desactivar voces de Google
UPDATE tbl_voces SET activo = false WHERE proveedor = 'google';
```

Y cambiar en `.env`:
```
TTS_PROVIDER=azure
```
