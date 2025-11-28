# 📚 Loom — Lectura Inteligente con Voces Naturales y Conversión Automática de PDFs

> Convierte libros y PDFs en experiencias auditivas fluidas con selección de voz, generación bajo demanda y seguimiento de progreso persistente. Diseñado para aprendizaje auditivo, accesibilidad y lectura aumentada.

---

## 🧭 Tabla de Contenido
1. 🚀 Visión General
2. ✨ Demo Rápida
3. 🎯 Motivación
4. 🗂️ Funcionalidades Clave
5. 🧱 Principios de Diseño
6. 🧑‍💻 Arquitectura General
7. 🔄 Flujos Operativos
8. 🧬 Modelo de Datos (ER Limpio y Actualizado)
9. 🔌 Endpoints REST (Resumen)
10. 🛠️ Servicios Internos y Scripts
11. ⚙️ Backend (Detalles Técnicos)
12. 📱 Frontend (Flutter)
13. 🧩 Tecnologías y Librerías (con logos)
14. ☁️ Infraestructura y Despliegue
15. 🔐 Variables de Entorno
16. 🧪 Estrategia de Procesamiento & Optimización TTS
17. ▶️ Instalación y Entorno Local
18. 🧊 Roadmap
19. 🕵️ Observabilidad y Mantenimiento
20. 🤝 Contribuir
21. 📄 Licencia

---

## 🚀 1. Visión General

Loom es un ecosistema (Backend Express + Flutter + Supabase + TTS Azure/Free) que ingiere PDFs, los segmenta inteligentemente y produce audios reproducibles de forma progresiva y escalable:
- Inicio rápido (primer audio disponible en segundos).
- Precarga inteligente de siguientes segmentos.
- Conmutación de proveedor TTS (Azure / Free) según disponibilidad.
- Persistencia y reanudación de progreso multi-voz por documento.
- Cache de audios para reducir costos y latencia.

---

## ✨ 2. Demo Rápida

- Subes un PDF, eliges una voz y reproduces de inmediato el primer segmento.
- El sistema pre-genera y cachea los próximos segmentos en segundo plano.
- Puedes pausar/continuar y cambiar de voz sin perder tu progreso.

---

## 🎯 3. Motivación

Dificultades comunes:
- Convertir PDFs a audio es tedioso y costoso.
- Baja retención y accesibilidad limitada en lectura tradicional.
- Bloqueos por latencia de TTS.

Cómo Loom lo resuelve:
- Conversión automática y progresiva por segmentos.
- Voces neuronales (Azure) o fallback gratuito (Google Translate TTS).
- Cache inteligente de audios y reintentos con degradación controlada.

---

## 🗂️ 4. Funcionalidades Clave

- Biblioteca enriquecida con autores, géneros y categorías.
- Subida de PDFs (multipart) + portada + clasificación.
- Segmentación por oraciones en chunks (~1,500 chars).
- TTS bajo demanda por segmento/voz con cache de resultados.
- Quick Start: primer audio síncrono, resto en background.
- Playlist inicial con precarga (cola opcional).
- Progreso persistente (intra_ms y offset global).
- Workers para segmentación, TTS paralelo y limpieza de cache.

---

## 🧱 5. Principios de Diseño

- Idempotencia en generación y cache de audios.
- Baja latencia percibida: priorizar primer segmento.
- Observabilidad y health-check básicos.
- Degradación segura: sin Azure → Free TTS; sin Redis → sin cola.
- Separación de responsabilidades (API, servicios, workers).

---

## 🧑‍💻 6. Arquitectura General

```mermaid
flowchart LR
  subgraph App[Flutter App]
    A[Auth + Usuario] --> B[Catálogo Libros]
    B --> C[Reproductor / Progreso]
    D[Subida PDF]
  end

  subgraph API[Express Backend]
    R[Router]
    CTRL[Controllers]
    SVC[Servicios TTS/PDF]
    Q[(Cola Redis BullMQ)]
    WK[Workers]
  end

  subgraph Data[Supabase]
    PG[(PostgreSQL)]
    ST[(Storage PDFs/Audios)]
    AUTH[Auth]
  end

  TTS[(Azure Speech / Free TTS)]

  D --> R
  A --> R
  B --> R
  C --> R
  R --> CTRL --> SVC --> PG
  SVC --> ST
  SVC --> TTS
  CTRL --> Q --> WK --> ST
  WK --> PG
```

---

## 🔄 7. Flujos Operativos

### 7.1 Subida PDF → Segmentación → Audios
```mermaid
sequenceDiagram
  participant F as Flutter
  participant E as Express API
  participant ST as Supabase Storage
  participant SEG as Worker Segmentación
  participant DB as Postgres
  participant TTS as Proveedor (Azure/Free)

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
  TTS-->>WK: MP3
  WK->>ST: Subir MP3
  WK->>DB: Cache tbl_audios
```

### 7.2 Reproducción On-Demand (Segmento)
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

### 7.3 Quick Start + Precarga
```mermaid
sequenceDiagram
  F->>E: POST /tts/libro/:libroId/quick-start (voiceId)
  E->>DB: Obtener documento y primer segmento
  E->>TTS: Generar primer audio
  TTS-->>E: MP3
  E->>ST: Subir audio
  E->>DB: Cache tbl_audios
  E-->>F: JSON {first_audio_url}
  E->>WK: (BG) Generar siguientes segmentos
```

---


## 📡 9. Endpoints REST (Resumen)

| Método | Ruta | Propósito | Parámetros clave |
|-------:|------|-----------|------------------|
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

---

## 🛠️ 10. Servicios Internos y Scripts

- Supabase Client: `config/supabase.js` → DB/Storage (service role).
- Postgres Client: `db/client.js` → conexión SQL nativa.
- Segmentación PDF: `workers/process_pdf.js` → extracción texto + segmentos.
- Cola TTS: `services/tts_queue.js` (BullMQ) → encolado batch.
- Worker TTS: `workers/tts_worker.js` → generación paralela (Azure/Free).
- Limpieza Cache: `workers/cache_cleanup.js` → TTL + LRU.
- Selector de Proveedor: `services/tts_provider.js` → Azure vs Free.
- Azure TTS: `services/azure_tts.js` → SSML + reintentos.
- Free TTS: `services/free_tts.js` → Google Translate TTS.
- Controladores TTS: `controllers/tts_controllers.js`.
- Controladores Libros: `controllers/books_controllers.js`.
- Controladores Usuario: `controllers/user_controllers.js`.
- Salud: `controllers/health_controller.js`.
- Migraciones SQL: `db/migrations/*.sql`.

---

## ⚙️ 11. Backend (Detalles Técnicos)

- Framework: Express 5 (ESM).
- Archivos: Supabase Storage (PDFs y MP3s).
- TTS: on-demand + cola opcional Redis.
- Reintentos Azure: backoff exponencial (2s, 4s, 6s) + fallback Free.
- Seguridad: claves service role sólo en backend; pendiente RLS.
- Logging: Morgan + logs enriquecidos en workers.

---

## 📱 12. Frontend (Flutter)

- Resolución dinámica de base URL.
- Reproductor con `just_audio` y precarga del siguiente segmento.
- Subida de PDF y portada (Multipart).
- Persistencia local de progreso + sync perezosa.
- Quick Start: escuchar mientras se generan siguientes segmentos.
- Autenticación con Firebase y ensureUser en backend.

---

## 🧩 13. Tecnologías y Librerías

- Backend:
  - ![Node.js](https://img.shields.io/badge/Node.js-339933?logo=nodedotjs&logoColor=white)
  - ![Express](https://img.shields.io/badge/Express-000000?logo=express&logoColor=white)
  - ![BullMQ](https://img.shields.io/badge/BullMQ-CC0000?logo=redis&logoColor=white)
  - ![Morgan](https://img.shields.io/badge/Morgan-000000?logo=npm&logoColor=white)
- Frontend:
  - ![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
  - ![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
  - ![just_audio](https://img.shields.io/badge/just__audio-3D3D3D?logo=musicbrainz&logoColor=white)
- Datos/Infra:
  - ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
  - ![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white)
  - ![Redis](https://img.shields.io/badge/Redis-DC382D?logo=redis&logoColor=white)
  - ![Azure](https://img.shields.io/badge/Azure%20Speech-0078D4?logo=microsoftazure&logoColor=white)
  - ![Firebase](https://img.shields.io/badge/Firebase-FFCA28?logo=firebase&logoColor=black)
  - ![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
  - ![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?logo=cloudflare&logoColor=white)

---

## ☁️ 14. Infraestructura y Despliegue

| Componente | Actual | Alternativas |
|-----------|--------|--------------|
| DB + Storage | Supabase | Postgres gestionado + S3/MinIO |
| TTS | Azure / Free | ElevenLabs, Polly, Piper local |
| Cola | Redis opcional | Redis Cloud, RabbitMQ, NATS |
| Backend | Render / Local | Docker Swarm / K8s |
| CDN | Pendiente | Cloudflare / Fastly para MP3 |

Escalado futuro: microservicio TTS, cache Redis para metadatos, compresión dinámica.

---

## 🔐 15. Variables de Entorno

Ver `backend/.env.example`.

| Variable | Propósito | Obligatoria | Ejemplo |
|----------|----------|-------------|---------|
| DATABASE_URL | Conexión Postgres | ✅ | postgresql://user:pass@host:5432/db |
| SUPABASE_URL | Proyecto Supabase | ✅ | https://xxx.supabase.co |
| SUPABASE_SERVICE_ROLE_KEY | Clave service (no frontend) | ✅ | (key) |
| AZURE_SPEECH_KEY | Azure TTS Key | ❌ | (key) |
| AZURE_SPEECH_REGION | Región Azure | ❌ | eastus |
| TTS_PROVIDER | Forzar azure|free | ❌ | azure |
| MOCK_TTS | Audios falsos | ❌ | true |
| REDIS_HOST | Host Redis | ❌ | localhost |
| REDIS_PORT | Puerto Redis | ❌ | 6379 |
| QUEUE_ENABLED | Habilitar cola | ❌ | true |
| CACHE_TTL_DAYS | TTL limpieza | ❌ | 60 |
| MAX_CACHE_PER_DOC_VOICE_MB | Cuota cache | ❌ | 100 |
| PORT | Puerto backend | ✅ | 3000 |

---

## 🧪 16. Estrategia de Procesamiento & Optimización TTS

- Playlist precarga: encola próximos 10 segmentos sin bloquear la respuesta.
- Quick Start: minimiza TTFA generando sólo el primer segmento.
- Cache adaptativa: `last_access_at` + `access_count` (LRU + TTL).
- Fallback proveedor: evita interrupciones por credenciales.
- Segmentación por oraciones y longitud para naturalidad prosódica.

---

## ▶️ 17. Instalación y Entorno Local

### Prerrequisitos
- Node.js LTS
- PostgreSQL / Supabase
- (Opcional) Redis para cola
- Flutter SDK (>= 3.9)
- (Opcional) Azure Speech

### Backend
```bash
git clone https://github.com/spalacioc05/Loom.git
cd Loom/backend
cp .env.example .env
# Edita valores (SUPABASE_URL, DATABASE_URL, etc.)
npm install
node test_db_connection.js
# Iniciar
node index.js   # o: npm run dev
```

### Workers
```bash
# Segmentación manual por libro
node workers/process_pdf.js <id_libro>

# TTS (si Redis habilitado)
node workers/tts_worker.js

# Limpieza de cache
node workers/cache_cleanup.js
```

### Frontend
```bash
cd ../frontend
flutter pub get
flutter run
```

### Quick Start desde Flutter (conceptual)
1. Selecciona libro.
2. Obtén `voiceId` vía `/voices`.
3. `POST /tts/libro/:id/quick-start` → reproducir `first_audio_url`.
4. Player observa nuevas URLs en `/tts/libro/:id/audios`.

---

## 🧊 18. Roadmap

- [ ] Descarga offline completa (batch + índice).
- [ ] Búsqueda semántica (embeddings por segmento).
- [ ] Marcadores y anotaciones sincronizadas.
- [ ] Ajuste dinámico velocidad/pitch en runtime.
- [ ] Multi-idioma con detección automática.
- [ ] Panel admin web (libros, voces, métricas).
- [ ] CDN + firmas temporales para audios.
- [ ] Integración con proveedores avanzados (ElevenLabs).
- [ ] Cache Redis para playlist y progreso.
- [ ] OpenAPI/Swagger + cliente generado.

---

## 🕵️ 19. Observabilidad y Mantenimiento

- `/health`: latencia y estado de tablas clave.
- Scripts `check_*`: integridad (huérfanos, faltantes).
- Métricas en limpieza: storage estimado, cantidad de audios, duración promedio.
- Recomendado a futuro: Prometheus + OpenTelemetry.

---

## 🤝 20. Contribuir

1. Fork y branch (`feat/...`).
2. Convenciones de commit: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`.
3. Incluye logs relevantes (workers, tiempos de generación).
4. No subir claves; usa `.env`.
5. Tests futuros: mock TTS y segmentación determinista.

---

## 📄 21. Licencia

Define una licencia (MIT o Apache-2.0 recomendado) y añade `LICENSE`.
