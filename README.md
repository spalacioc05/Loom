# 📚 Loom — Lectura Inteligente con Voces Naturales y Conversión Automática de PDFs

> Convierte libros y PDFs en experiencias auditivas fluidas con selección de voz, generación bajo demanda y seguimiento de progreso persistente. Diseñado para aprendizaje auditivo, accesibilidad y lectura asistida.

---

## 🧭 Tabla de Contenido
1. 🚀 Visión General
2. 🎯 Motivación
3. 🗂️ Funcionalidades Clave (Resumen + Detalle)
4. 🧱 Principios de Diseño
5. 🧑‍💻 Arquitectura General (Capas y Componentes)
6. 🔄 Flujos Operativos Principales
7. 🧬 Modelo de Datos (ER Actualizado)
8. 📡 Endpoints REST (Resumen)
9. 🛠️ Servicios Internos y Scripts (Tabla Completa)
10. ⚙️ Backend (Detalles Técnicos)
11. 📱 Frontend (Flutter App)
12. ☁️ Infraestructura y Despliegue
13. 🔐 Variables de Entorno
14. 🧪 Estrategia de Procesamiento & Optimización TTS
15. ▶️ Instalación y Entorno Local
16. 🧊 Roadmap / Futuras Mejores
17. 🕵️ Observabilidad y Mantenimiento
18. 🤝 Contribuir
19. 📄 Licencia

---

## 🚀 1. Visión General
Loom es un ecosistema (Backend Express + Flutter + Storage Supabase + TTS Azure/Free) que ingiere PDFs, los segmenta inteligentemente y produce audios reproducibles de forma progresiva y escalable. Prioriza:
- Inicio rápido (primer audio disponible en segundos).
- Precarga inteligente de siguientes segmentos.
- Capacidad de alternar proveedor de TTS (Azure vs Free Google-Translate TTS) según disponibilidad.
- Persistencia y reanudación de progreso multi-voz por documento.

## 🎯 2. Motivación
Problemas comunes en lectura tradicional: baja retención auditiva, accesibilidad limitada, fricción para convertir contenidos personales. Loom soluciona:
- Conversión automática de PDFs sin pasos manuales complejos.
- Voces neuronales (cuando hay credenciales Azure) o fallback gratuito.
- Modelo incremental: se puede escuchar mientras se sigue generando.
- Cache y reutilización de audios (evita costos repetidos).

## 🗂️ 3. Funcionalidades Clave

| Área | Funcionalidad | Detalle | Estado |
|------|---------------|---------|--------|
| Biblioteca | Listado enriquecido | Autores, géneros, categorías agregadas vía joins | ✅ |
| Subida PDF | Multipart + análisis | Extrae páginas, palabras y lanza segmentación background | ✅ |
| Segmentación | Oraciones → chunks | ~1500 chars, salta metadatos iniciales (~3000 chars) | ✅ |
| TTS On-Demand | /tts/segment | Genera y cachea por segmento/voz | ✅ |
| Quick Start | Primer audio síncrono | Genera 1er segmento y lanza 3 siguientes en background | ✅ |
| Playlist | Request progresivo | Devuelve primeros 5 segmentos + precarga siguientes | ✅ |
| Progreso | Persistencia local + backend | Guarda intra_ms + offset global de caracteres | ✅ |
| Biblioteca Usuario | Asociación libros ↔ usuario | Tabla `tbl_libros_x_usuarios` con progreso ligero | ✅ |
| Precarga Batch | Worker Redis | Encola segmentos para generación paralela | ✅ (opcional) |
| Limpieza Cache | TTL + LRU | Script elimina audios antiguos / excedidos | ✅ |
| Multi Proveedor | Azure / Free | Selección automática (variables o fallback) | ✅ |

## 🧱 4. Principios de Diseño
- Idempotencia: generación de audio usa UPSERT/ON CONFLICT para evitar duplicados.
- Latencia percibida baja: entregar primer segmento rápido y diferir el resto.
- Observabilidad mínima: endpoint `/health` verifica DB y voces.
- Degradación controlada: sin Azure → Free TTS; sin Redis → cola deshabilitada.
- Aislamiento de responsabilidades: segmentación separada en worker y servicios TTS desacoplados.

## 🧑‍💻 5. Arquitectura General

```mermaid
flowchart LR
  subgraph Móvil[Flutter App]
    A[Auth + Usuario] --> B[Catálogo Libros]
    B --> C[Reproductor / Progreso]
    D[Uploader PDF]
  end

  subgraph API[Express Backend]
    R[Router / Endpoints]
    CTRL[Controllers]
    SVC[Servicios TTS / PDF]
    Q[(Cola Redis BullMQ)]
    WK[Workers]
  end

  subgraph Data[Supabase]
    PG[(Postgres)]
    ST[(Storage PDFs/Audios)]
    AUTH[Auth]
  end

  TTSProv[(Azure / Free TTS)]

  D --> R
  A --> R
  B --> R
  C --> R
  R --> CTRL --> SVC --> PG
  SVC --> ST
  SVC --> TTSProv
  CTRL --> Q --> WK --> ST
  WK --> PG
```

### Capas
| Capa | Rol | Archivos principales |
|------|-----|---------------------|
| Routing | Define endpoints REST | `routes/routes.js` |
| Controllers | Orquestación HTTP | `controllers/*.js` |
| Services | Lógica de dominio (TTS provider selector, cola, generación) | `services/*.js` |
| Workers | Procesamiento asíncrono (segmentación, generación paralela, limpieza) | `workers/*.js` |
| DB Access | Conexión Postgres / Supabase | `db/client.js`, migraciones SQL |

## 🔄 6. Flujos Operativos Principales

### 6.1 Subida PDF → Segmentación → Audios
```mermaid
sequenceDiagram
  participant F as Flutter
  participant E as Express API
  participant ST as Supabase Storage
  participant SEG as Worker Segmentación
  participant DB as Postgres
  participant TTS as Provider (Azure/Free)

  F->>E: POST /libros (multipart PDF + portada + categorías)
  E->>ST: Guardar PDF
  E->>DB: INSERT libro + categorías
  E-->>F: 201 Libro creado (segmentación async)
  E->>SEG: processPdf(libro_id) (background)
  SEG->>ST: Descargar PDF
  SEG->>DB: Crear documento (estado=procesando)
  SEG->>SEG: Extraer texto + saltar metadatos
  SEG->>DB: Insertar segmentos (orden 0..n)
  SEG->>DB: Update documento (estado=listo)
  SEG->>Q: Encolar primeros segmentos (opcional)
  Q->>WK: Jobs generación TTS
  WK->>TTS: Synthesize
  TTS-->>WK: Audio
  WK->>ST: Subir MP3
  WK->>DB: Cache tbl_audios
```

### 6.2 Reproducción On-Demand (Segmento aislado)
```mermaid
sequenceDiagram
  participant F as Flutter
  participant E as API
  participant DB as Postgres
  participant ST as Storage
  participant TTS as Provider

  F->>E: GET /tts/segment?doc=...&voice=...&segment=...
  E->>DB: Buscar cache tbl_audios
  alt Existe
    E-->>F: 302 Redirect a audio_url
  else No existe
    E->>DB: Obtener texto segmento + voz
    E->>TTS: Generar audio
    TTS-->>E: MP3 Buffer
    E->>ST: Subir audio
    E->>DB: Insert/Update tbl_audios
    E-->>F: 302 Redirect a audio_url
  end
```

### 6.3 Quick Start
```mermaid
sequenceDiagram
  F->>E: POST /tts/libro/:libroId/quick-start (voiceId)
  E->>DB: Obtener documento y primer segmento
  E->>TTS: Generar primer audio
  TTS-->>E: MP3
  E->>ST: Subir audio
  E->>DB: Cache tbl_audios
  E-->>F: JSON {first_audio_url}
  E->>WK: (Background) Generar siguientes 3 segmentos
```

### 6.4 Playlist Inicial + Precarga
```mermaid
sequenceDiagram
  F->>E: POST /tts/playlist {document_id, voice_id}
  E->>DB: Resolver documento + estado
  E->>DB: Obtener primeros 5 segmentos + audios
  E->>Q: Encolar próximos 10 pendientes
  E-->>F: JSON {items[], start_segment_id}
```

### 6.5 Progreso
```mermaid
sequenceDiagram
  F->>E: POST /progress {document_id, voice_id, segment_id, intra_ms}
  E->>DB: UPSERT tbl_progreso
  F->>E: GET /progress?doc=...
  E->>DB: SELECT último progreso
  E-->>F: JSON progreso
```

## 🧬 7. Modelo de Datos (ER Actualizado)

Se muestra el esquema derivado (simplificado visual) del SQL proporcionado. No ejecutar directamente; fines documentales.

```mermaid
erDiagram
  tbl_usuarios ||--o{ tbl_libros_x_usuarios : "lee"
  tbl_libros ||--o{ tbl_libros_x_autores : "tiene"
  tbl_autores ||--o{ tbl_libros_x_autores : "participa"
  tbl_libros ||--o{ tbl_libros_x_generos : "clasifica"
  tbl_generos ||--o{ tbl_libros_x_generos : "etiqueta"
  tbl_libros ||--o{ tbl_libros_x_categorias : "categ"
  tbl_categorias ||--o{ tbl_libros_x_categorias : "aplica"
  tbl_libros ||--o{ tbl_documentos : "procesa"
  tbl_documentos ||--o{ tbl_segmentos : "segmenta"
  tbl_segmentos ||--o{ tbl_audios : "audio"
  tbl_voces ||--o{ tbl_audios : "voz"
  tbl_voces ||--o{ tbl_progreso : "voz"
  tbl_documentos ||--o{ tbl_progreso : "track"
  tbl_segmentos ||--o{ tbl_progreso : "posicion"

  tbl_libros {
    bigint id_libro PK
    text titulo
    text descripcion
    date fecha_publicacion
    text portada
    text archivo
    integer paginas
    integer palabras
    text categoria (legacy)
  }
  tbl_documentos {
    uuid id PK
    integer libro_id FK
    varchar estado
    integer total_segmentos
    integer total_caracteres
    timestamptz updated_at
  }
  tbl_segmentos {
    uuid id PK
    uuid documento_id FK
    integer orden
    integer char_inicio
    integer char_fin
    text texto
  }
  tbl_audios {
    uuid id PK
    uuid documento_id FK
    uuid segmento_id FK
    uuid voz_id FK
    text audio_url
    integer duracion_ms
  }
  tbl_voces {
    uuid id PK
    varchar proveedor
    varchar codigo_voz
    varchar idioma
    jsonb configuracion
    boolean activo
  }
  tbl_progreso {
    uuid id PK
    uuid usuario_id
    uuid documento_id FK
    uuid voz_id FK
    uuid segmento_id FK
    integer intra_ms
    integer offset_global_char
  }
```

### Notas:
- `orden=0` en `tbl_segmentos` actúa como offset inicial tras saltar metadatos (segmento metadata). Reproducción real comienza en `orden>0`.
- `tbl_libros_x_usuarios` almacena progreso ligero adicional (`fecha_ultima_lectura`, `progreso`, etc.).
- Cache de audio (`tbl_audios`) permite métricas de acceso (`access_count`, `last_access_at`).

## 📡 8. Endpoints REST (Resumen)

| Método | Ruta | Propósito | Parámetros clave |
|--------|------|-----------|------------------|
| GET | /disponibles | Listar libros enriquecidos | - |
| GET | /categorias | Listar categorías | - |
| GET | /biblioteca/:userId | Biblioteca usuario | userId (bigint) |
| POST | /biblioteca/agregar | Añadir libro a biblioteca | userId, bookId |
| DELETE | /biblioteca/remover | Quitar libro | userId, bookId |
| POST | /libros | Subir libro (PDF + portada) | multipart fields |
| POST | /usuarios/ensure | Upsert usuario | firebaseUid/email |
| GET | /usuarios/by-firebase/:firebaseUid | Obtener usuario | firebaseUid |
| GET | /voices | Listar voces activas | - |
| POST | /tts/libro/:libroId/quick-start | Primer audio inmediato | voiceId |
| POST | /tts/playlist | Playlist inicial | document_id/libro_id, voice_id |
| GET | /tts/segment | Audio segmento (redirige) | doc/libro, voice, segment |
| GET | /tts/libro/:libroId/audios | Lista audios + autoGenerate | libroId, autoGenerate?, voiceId? |
| POST | /progress | Guardar progreso | document_id, voice_id, segment_id, intra_ms |
| GET | /progress | Obtener progreso | doc |
| GET | /health | Salud sistema | - |
| GET | /ping | Diagnóstico rápido | - |

## 🛠️ 9. Servicios Internos y Scripts

| Nombre | Tipo | Archivo | Responsabilidad Principal | Detalles / Notas |
|--------|------|---------|---------------------------|------------------|
| Supabase Client | Config | `config/supabase.js` | Acceso a Storage/DB (service role) | Mantener fuera de frontend |
| Postgres Client | DB | `db/client.js` | Conexión SQL nativa | Usa `postgres` lib SSL require |
| Segmentación PDF | Worker | `workers/process_pdf.js` | Extraer texto y crear segmentos | Salta metadatos iniciales, hash contenido |
| Cola TTS | Servicio | `services/tts_queue.js` | Encolado batch (BullMQ) | Auto deshabilita si Redis no disponible |
| Worker TTS | Worker | `workers/tts_worker.js` | Generación paralela (Azure) | Concurrencia 6, limiter 10/s |
| Limpieza Cache | Worker | `workers/cache_cleanup.js` | TTL + LRU + métricas | Control por env: TTL & cuota |
| Provider Selector | Servicio | `services/tts_provider.js` | Decide Azure vs Free | Fallback si no hay credenciales |
| Azure TTS | Servicio | `services/azure_tts.js` | SSML, reintentos, pitch/rate | Mock opcional `MOCK_TTS` |
| Free TTS | Servicio | `services/free_tts.js` | Google Translate TTS | Sin variación real de voces |
| Playlist / Segment Audio | Controller | `controllers/tts_controllers.js` | Generar, cachear y playlist | Quick-start, precarga batch |
| Libros / Biblioteca | Controller | `controllers/books_controllers.js` | CRUD libros y subida PDF | Subida portada y categorías |
| Usuario | Controller | `controllers/user_controllers.js` | Asegurar usuario | Usa firebaseUid/email |
| Salud | Controller | `controllers/health_controller.js` | Reporte integridad | Variables, tablas |
| Migraciones SQL | Data | `db/migrations/*.sql` | Evolución esquema | Voces, usuarios, TTS, categorías |
| Diagnóstico TTS | Script | `diagnose_tts_status.js` | Estado generación por libro | Útil para auditoría |
| Generación Batch | Script | `generate_batch_audios.js` | Lote audios faltantes | Pre-carga manual |
| Generar Primeros Audios | Script | `generate_first_audios_all_books.js` | Bootstrapping catálogo | Primer segmento por libro |
| Limpieza Azure Voces | Script | `cleanup_azure_voices.js` | Quitar voces obsoletas | Pre migración a Free |
| Checkers DB | Scripts | `check_*` | Integridad (audios, libros, segmentos) | Mantenimiento |

## ⚙️ 10. Backend (Detalles Técnicos)
- Framework: Express 5 (module type ESM).
- Almacenamiento de archivos: Supabase Storage (bucket `archivos_libros` PDFs / `audios_tts` MP3s).
- Generación TTS: Función on-demand + cola opcional via Redis.
- Estrategia de reintentos TTS Azure: exponencial (2s, 4s, 6s) + fallback REST.
- Seguridad básica: Restricción por claves service role (no exponer en frontend). (Pendiente: auth robusta para progreso por usuario real y RLS).
- Logging: Morgan (+ console detallado en workers).

## 📱 11. Frontend (Flutter)
- Resolución dinámica de base URL (`ApiService.resolveBaseUrl()`).
- Reproductor basado en `just_audio` + precarga manual siguiente segmento.
- Subida PDF y portada con `MultipartRequest` (muestra tamaños y logs detallados).
- Persistencia local de progreso (SharedPreferences) + sincronización perezosa backend.
- Quick Start UX: usuario escucha primer segmento mientras se generan los siguientes.
- Autenticación: Firebase + ensureUser en backend (vincula `firebase_uid` ↔ `tbl_usuarios`).

## ☁️ 12. Infraestructura y Despliegue
| Componente | Opción Actual | Alternativas Futuras |
|------------|---------------|----------------------|
| DB + Storage | Supabase | Postgres administrado + S3/MinIO |
| TTS | Azure / Free | Proveedor multi (ElevenLabs, Polly, Local Piper) |
| Cola | Redis opcional | Cloud Redis / RabbitMQ / NATS |
| Backend | Render / Local Dev | Docker Swarm / K8s |
| CDN | (Pendiente) | Cloudflare / Fastly para MP3 |

Escalado futuro: microservicio TTS independiente, caché Redis para metadatos, compresión dinámica de audio.

## 🔐 13. Variables de Entorno
Ver `backend/.env.example`.

| Variable | Propósito | Obligatoria | Ejemplo |
|----------|----------|-------------|---------|
| DATABASE_URL | Conexión Postgres | ✅ | postgresql://user:pass@host:5432/db |
| SUPABASE_URL | Proyecto Supabase | ✅ | https://xxx.supabase.co |
| SUPABASE_SERVICE_ROLE_KEY | Clave service (no frontend) | ✅ | (key) |
| AZURE_SPEECH_KEY | Azure TTS Key | ❌ (si Free) | (key) |
| AZURE_SPEECH_REGION | Región Azure | ❌ | eastus |
| TTS_PROVIDER | Forzar azure|free | ❌ | azure |
| MOCK_TTS | Generar audios falsos | ❌ | true |
| REDIS_HOST | Host Redis | ❌ | localhost |
| REDIS_PORT | Puerto Redis | ❌ | 6379 |
| QUEUE_ENABLED | Habilitar cola | ❌ | true |
| CACHE_TTL_DAYS | TTL limpieza | ❌ | 60 |
| MAX_CACHE_PER_DOC_VOICE_MB | Cuota cache | ❌ | 100 |
| PORT | Puerto backend | ✅ | 3000 |

## 🧪 14. Estrategia de Procesamiento & Optimización TTS
- Precarga: playlist encola próximos 10 segmentos sin bloquear respuesta inicial.
- Quick Start: reduce Time-To-First-Audio (TTFA) al sintetizar sólo primer segmento.
- Cache adaptativa: acceso actualiza `last_access_at` y `access_count` (LRU + TTL script).
- Fallback proveedor: evita interrupción cuando faltan credenciales.
- Segmentación controlada por longitud y división por oraciones → mayor naturalidad en prosodia.

## ▶️ 15. Instalación y Entorno Local

### Prerrequisitos
- Node.js LTS
- PostgreSQL / Supabase proyecto (recomendado) 
- (Opcional) Redis para cola
- Flutter SDK (>=3.9)
- Credenciales Azure Speech (si deseas calidad superior)

### Backend
```bash
git clone https://github.com/spalacioc05/Loom.git
cd Loom/backend
cp .env.example .env
# Edita valores (SUPABASE_URL, DATABASE_URL, etc.)
npm install
# (Opcional) Ejecutar migraciones en Supabase (copiar SQL)
node test_db_connection.js
# Iniciar
node index.js   # o: npm run dev
```

### Worker Segmentación Manual
```bash
node workers/process_pdf.js <id_libro>
```

### Worker TTS (si Redis habilitado)
```bash
node workers/tts_worker.js
```

### Limpieza Caché
```bash
node workers/cache_cleanup.js
```

### Frontend
```bash
cd ../frontend
flutter pub get
flutter run
```

### Quick Start desde Flutter (conceptual)
1. Seleccionar libro.
2. Obtener `voiceId` vía `/voices`.
3. Llamar `POST /tts/libro/:id/quick-start` → reproducir `first_audio_url`.
4. Mientras tanto player observa nuevas URLs en `/tts/libro/:id/audios`.

## 🧊 16. Roadmap / Futuras Mejores
- [ ] Descarga offline completa de libro (batch background + index).
- [ ] Búsqueda semántica (embeddings segmentos).
- [ ] Marcadores y anotaciones sincronizadas.
- [ ] Ajuste dinámico de velocidad/pitch en runtime.
- [ ] Soporte multi-idioma (inglés, francés) con detección automática.
- [ ] Panel admin web (gestión libros, voces, métricas).
- [ ] CDN y firmas temporales para audios.
- [ ] Integración con proveedor avanzado (ElevenLabs) y evaluación de calidad.
- [ ] Cache Redis para playlist y progreso.
- [ ] OpenAPI/Swagger + cliente generado.

## 🕵️ 17. Observabilidad y Mantenimiento
- `/health`: latencia y estado de tablas críticas.
- Scripts `check_*`: verifican integridad (segmentos huérfanos, audios faltantes, etc.).
- Métricas base en limpieza: storage estimado, audios cacheados, duración promedio.
- Recomendado agregar: Prometheus exporter (futuro), trazas OpenTelemetry para generación TTS.

## 🤝 18. Contribuir
1. Fork & branch (`feat/...`).
2. Mantén convenciones de commits: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`.
3. Adjunta logs relevantes de workers o tiempos de generación en PR.
4. No subir claves (usa `.env`).
5. Tests futuros: mock de TTS y segmentación determinista.

## 📄 19. Licencia
Considera MIT o Apache-2.0. Añade archivo `LICENSE` si aún no existe.

---
### Notas Finales
- Este README refleja estado actual del código inspeccionado.
- Si agregas autenticación robusta (JWT / Supabase Auth RLS), documenta flujo token.
- Para documentación API ampliada se sugiere crear `docs/api.md` y exportar OpenAPI.

¿Necesitas ahora un archivo adicional con especificación OpenAPI o documentación de workers? Pídelo y lo genero.
