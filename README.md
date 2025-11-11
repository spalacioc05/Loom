# 📚 Loom — Lectura con Voces Naturales e Inteligencia de Contexto

> Convierte libros y PDFs en experiencias auditivas fluidas con voces humanas naturales, personalización y seguimiento de progreso. Ideal para personas con preferencia de aprendizaje auditivo o que desean “leer escuchando”.

---

## 🧭 Tabla de Contenido
1. 🚀 Visión General
2. 🎯 Motivación y Problema que Resuelve
3. 🗂️ Funcionalidades Clave
4. 🧑‍💻 Arquitectura General
5. 🔄 Flujo de Procesamiento de un PDF → Audio
6. 🧬 Modelo de Datos (ER Simplificado)
7. 🛠️ Tecnologías y Librerías
8. ⚙️ Backend (ExpressJS)
9. 📱 Frontend (Flutter)
10. ☁️ Infraestructura y Despliegue
11. 🔐 Variables de Entorno
12. 🧪 Scripts y Utilidades
13. ▶️ Pasos de Instalación (Local / Dev)
14. 🧊 Roadmap / Futuras Mejores
15. 🤝 Contribuir
16. 📄 Licencia

---

## 🚀 1. Visión General

Loom es una aplicación móvil multiplataforma (Flutter) que:
- Ofrece una biblioteca de libros categorizados.
- Permite subir tus propios PDFs.
- Convierte texto en narraciones con voces naturales usando Azure Cognitive Services (TTS Neural).
- Ofrece selección de voz, control de reproducción, reanudación y seguimiento de progreso por usuario.
- Facilita acceso inclusivo a contenidos para usuarios con preferencia de aprendizaje auditivo.

---

## 🎯 2. Motivación y Problema

Muchos lectores potenciales no conectan emocional o cognitivamente con la lectura silenciosa tradicional:
- Modelo VARK de estilos de aprendizaje: algunos retienen más escuchando.
- Lectura mecánica ≠ comprensión profunda.
- Voces robóticas afectan inmersión y retención.

Loom ofrece:
- Voces naturales con pausas, prosodia y entonación humanas.
- Conversión ágil de PDFs personales y libros públicos.
- Experiencia fluida en móvil sin complejidad técnica para el usuario.

---

## 🗂️ 3. Funcionalidades Clave

| Categoría | Descripción |
|----------|-------------|
| Biblioteca | Catálogo con categorías y filtrado. |
| Subida de PDF | Carga, segmentación y procesamiento asincrónico. |
| TTS Avanzado | Voces neuronales de Azure (selección por idioma/género/tono). |
| Progreso | Último segmento reproducido por libro. |
| Perfiles | Autenticación (Google / Supabase Auth). |
| Streaming de Audio | Reproducción de segmentos para inicio rápido. |
| Gestión Personal | Biblioteca privada de PDFs del usuario. |
| Scripts de Mantenimiento | Limpieza, validación y migraciones. |

---

## 🧑‍💻 4. Arquitectura General

```mermaid
flowchart LR
  subgraph Client[Flutter App]
    UI[UI / Navegación]
    Auth[Auth SDK]
    Player[Audio Player]
    Upload[Upload PDFs]
  end

  subgraph Backend[API ExpressJS]
    API[REST Endpoints]
    Proc[PDF Processor]
    Seg[Segmentador]
    Queue[(Job Queue opcional)]
    TTS[Generador Azure TTS]
  end

  subgraph Supabase[Supabase / Postgres + Storage]
    DB[(Postgres)]
    Storage[(Storage de PDFs / Audios)]
    AuthSvc[Auth]
  end

  AzureTTS[Azure Cognitive Services TTS]

  UI --> Auth --> API
  Upload --> API
  API --> Proc --> Seg --> TTS
  TTS --> Storage
  Seg --> DB
  API --> DB
  Player --> API
  API --> Storage
  API --> AzureTTS
```

---

## 🔄 5. Flujo de Procesamiento de un PDF → Audio

```mermaid
sequenceDiagram
  participant U as Usuario (App)
  participant A as API Express
  participant P as Procesador PDF
  participant S as Segmentador
  participant T as Azure TTS
  participant D as DB (Supabase)
  participant ST as Storage

  U->>A: Subir PDF
  A->>ST: Guardar PDF original
  A->>P: Iniciar procesamiento (job)
  P->>S: Extraer texto y segmentar
  S->>D: Insertar metadatos y segmentos
  loop Por segmento
    A->>T: Solicitar síntesis
    T-->>A: Audio generado
    A->>ST: Guardar audio (segmento_X.mp3)
    A->>D: Actualizar estado segmento
  end
  U->>A: Reproducir
  A->>D: Consultar progreso
  A->>ST: Obtener audio streaming
  ST-->>U: Enviar chunk(s)
```

---

## 🧬 6. Modelo de Datos (ER Simplificado)

```mermaid
erDiagram
  usuarios ||--o{ libros : "sube"
  usuarios ||--o{ progreso : "tiene"
  libros ||--o{ segmentos : "se compone de"
  libros ||--o{ voces_asignadas : "voz preferida"
  usuarios ||--o{ biblioteca_privada : "PDFs propios"

  usuarios {
    uuid id
    text email
    text display_name
    timestamp created_at
  }

  libros {
    uuid id
    text titulo
    text autor
    text categoria
    text cover_url
    boolean publico
    timestamp created_at
  }

  segmentos {
    uuid id
    uuid libro_id
    integer orden
    text texto
    text audio_url
    enum estado
  }

  progreso {
    uuid id
    uuid usuario_id
    uuid libro_id
    uuid segmento_actual_id
    integer posicion_ms
    timestamp updated_at
  }

  voces_asignadas {
    uuid id
    uuid libro_id
    text voz_azure
    text idioma
  }
```

(Ajustar a tablas reales si difieren.)

---

## 🛠️ 7. Tecnologías y Librerías

Badges sugeridos (puedes activarlos en el repositorio):

- ![Express](https://img.shields.io/badge/Express.js-000000?logo=express&logoColor=white)
- ![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
- ![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white)
- ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
- ![Azure](https://img.shields.io/badge/Azure%20Cognitive%20Services-0078D4?logo=microsoftazure&logoColor=white)
- ![Render](https://img.shields.io/badge/Render-46E3B7?logo=render&logoColor=black)
- ![Node.js](https://img.shields.io/badge/Node.js-339933?logo=node.js&logoColor=white)

### Backend (parcial estimado — verifica con package.json)
Dependencias típicas (ajusta con las reales):
- express
- cors
- dotenv
- pg / supabase-js
- multer (subida de archivos)
- pdf-parse (u otra librería de extracción PDF)
- azure-cognitiveservices-speech-sdk
- node-fetch / axios
- uuid
- bull / agenda / (si usas cola de trabajos; validar)
- winston / pino (logging si aplica)

Scripts utilitarios detectados por nombres de archivo:
- add_voices.js: Inicializa/inyecta catálogo de voces.
- process_pdf_standalone.js: Pipeline manual de procesamiento.
- generate_tts_audio.cjs / test_single_tts.cjs: Generación y prueba de audio TTS.
- check_* (audios, books, db, segments, usuarios): Sanitización / verificación de integridad.
- clean_segments.js: Limpieza de segmentos huérfanos.
- run_tts_migration.js: Migración relacionada a voces o estructura de TTS.

### Frontend (Flutter)
- Material / Cupertino widgets.
- HTTP / dio para consumo de API.
- Provider / Riverpod / Bloc (elegir y documentar cuál se usa).
- just_audio / audioplayers para reproducción.
- file_picker / pdfx (si se previsualiza).
- google_sign_in / firebase_auth (si se integra con Supabase OAuth) o supabase_flutter.

---

## ⚙️ 8. Backend (ExpressJS)

Características:
- Endpoints REST para: autenticación (vía tokens de Supabase), listado de libros, subida de PDFs, estado de procesamiento, obtención de audio segmentado y progreso.
- Procesos batch/sincrónicos híbridos: Segmentación + TTS asíncrono.
- Scripts de mantenimiento reutilizables (prefijo check_*, test_*).
- Posible soporte a colas (si decides escalar la generación de TTS en workers separados).

Patrón sugerido de capas:
- /routes → Definición de endpoints.
- /controllers → Lógica de orquestación HTTP.
- /services → Reglas de negocio (segmentación, TTS, progreso).
- /db → Acceso/Postgres (SQL directo o supabase-js).
- /workers → Jobs de procesamiento (TTS masivo, limpieza).

---

## 📱 9. Frontend (Flutter)

Módulos sugeridos:
- auth/ → manejo de sesión.
- library/ → lista y detalles de libros.
- player/ → control de reproducción continuo (mantener progreso).
- upload/ → flujo de selección de archivo y envío.
- voices/ → exploración y selección de voces.
- settings/ → preferencias del usuario.

UX Clave:
- Reproducción por streaming de segmentos consecutivos con precarga.
- Indicador de estado (Procesando / Listo / Error) por libro propio.
- Persistencia offline básica (metadatos y posición).

---

## ☁️ 10. Infraestructura y Despliegue

| Componente | Plataforma | Notas |
|------------|-----------|-------|
| Backend API | Render | Deploy continuo (desde main o branch deploy). |
| Base de Datos | Supabase (Postgres) | Migraciones y políticas RLS si aplica. |
| Storage | Supabase Storage | PDF original + audios generados (carpetas por libro/segmento). |
| TTS | Azure Cognitive Services | Neural Voices. |
| App | Flutter (APK distribuible) | Posible futura publicación en Play Store. |

Estrategia de escalado futuro:
- Extraer TTS a microservicio worker.
- CDN para audio segmentado.
- Cache de metadatos en Redis.

---

## 🔐 11. Variables de Entorno

Consulta el archivo `backend/.env.example` (ajusta esta lista según contenido real). Ejemplo:

```
PORT=3000
NODE_ENV=development

SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_KEY=
DATABASE_URL=postgresql://user:pass@host:5432/db

AZURE_SPEECH_KEY=
AZURE_SPEECH_REGION=

STORAGE_BUCKET=audios
RENDER_PUBLIC_URL=

JWT_SECRET= (si se usa token propio complementario)
```

---

## 🧪 12. Scripts y Utilidades

| Script | Descripción |
|--------|-------------|
| add_voices.js | Registra voces disponibles en DB. |
| process_pdf_standalone.js | Corre pipeline fuera del servidor (debug / batch). |
| generate_tts_audio.cjs | Genera audio de un conjunto de segmentos. |
| test_azure_tts.js / test_single_tts.cjs | Verifica credenciales y calidad de TTS. |
| check_db.js | Valida estructura / tablas. |
| check_segments.js | Revisa integridad de segmentos vs. libros. |
| clean_segments.js | Elimina residuos. |
| run_tts_migration.js | Migra esquema relacionado a TTS. |
| test_pdf_parse.js | Verifica extracción de texto. |

---

## ▶️ 13. Pasos de Instalación (Local / Dev)

### Prerrequisitos
- Node.js LTS
- Docker + Docker Compose (para Postgres local si no usas Supabase remoto)
- Cuenta Azure + recurso Cognitive Services (Speech)
- Flutter SDK

### Backend
```bash
git clone https://github.com/spalacioc05/Loom.git
cd Loom/backend
cp .env.example .env
# Rellena variables
npm install
# Opcional: iniciar Postgres local
docker compose up -d
# Probar conexión
node test_db_connection.js
# Inicializar voces
node add_voices.js
# Iniciar servidor
npm start  # o node index.js
```

### Frontend
```bash
cd ../frontend
flutter pub get
flutter run
```

### Procesar un PDF manualmente
```bash
node process_pdf_standalone.js --file /ruta/a/archivo.pdf --libro "Mi Libro"
```

---

## 🧊 14. Roadmap / Futuras Mejoras

- [ ] Reproducción continua con buffering inteligente.
- [ ] Búsqueda semántica dentro de libros.
- [ ] Marcadores y notas personales sincronizadas.
- [ ] Ajuste de velocidad y tono dinámico (si Azure lo permite en runtime).
- [ ] Descarga offline de audios (modo sin conexión).
- [ ] Filtro avanzado de voces por características emocionales.
- [ ] Panel administrativo web.
- [ ] Métricas de uso (segmentos escuchados, conversión completada).

---

## 🤝 15. Contribuir

1. Haz fork.
2. Crea una rama: `feat/nueva-funcionalidad`.
3. Asegura estilo consistente (añadir sección sobre linter si procede).
4. PR bien descrito incluyendo screenshots / logs de test.

Convenciones sugeridas:
- Commits: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`.
- Nombres de archivos: snake_case para scripts utilitarios, camelCase en código de negocio.

---

## 📄 16. Licencia

(Añade aquí el tipo de licencia; si no has elegido una, considera MIT.)

---

## 📝 Notas sobre este README

- La lista de dependencias y variables debe refinarse con el contenido real de `package.json` y `.env.example`.
- El listado de archivos backend mostrado fue parcial (limitación de exploración automática); si hay más carpetas (e.g. middlewares, utils), incorpóralas en la sección de arquitectura interna.
- Puedes extraer capturas o GIFs de la app para añadir una sección “Vista Previa”.

---

¿Deseas que prepare también documentación separada (por ejemplo `/docs/arquitectura.md`, `/docs/api.md`, `/docs/pipeline_tts.md`) o un OpenAPI/Swagger para los endpoints? Indícame y lo elaboro.
