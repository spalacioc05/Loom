-- Migración inicial para sistema TTS
-- Ejecutar en Supabase SQL Editor

-- Tabla de documentos (libros con texto procesado)
CREATE TABLE IF NOT EXISTS tbl_documentos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  libro_id INTEGER NOT NULL REFERENCES tbl_libros(id_libro) ON DELETE CASCADE,
  estado VARCHAR(20) DEFAULT 'pendiente', -- pendiente|procesando|listo|error
  texto_hash VARCHAR(64), -- SHA256 del texto completo
  total_caracteres INTEGER,
  total_segmentos INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(libro_id)
);

-- Tabla de segmentos (chunks de texto ~1500 chars)
CREATE TABLE IF NOT EXISTS tbl_segmentos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id UUID NOT NULL REFERENCES tbl_documentos(id) ON DELETE CASCADE,
  orden INTEGER NOT NULL, -- orden secuencial del segmento
  pagina_inicio INTEGER,
  pagina_fin INTEGER,
  char_inicio INTEGER NOT NULL, -- offset inicial en texto completo
  char_fin INTEGER NOT NULL, -- offset final en texto completo
  texto TEXT NOT NULL,
  texto_hash VARCHAR(64), -- SHA256 del texto del segmento
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(documento_id, orden)
);

-- Índice para búsqueda por offset
CREATE INDEX IF NOT EXISTS idx_segmentos_offset ON tbl_segmentos(documento_id, char_inicio, char_fin);

-- Tabla de voces disponibles
CREATE TABLE IF NOT EXISTS tbl_voces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  proveedor VARCHAR(20) NOT NULL, -- azure|gcp|polly|coqui
  codigo_voz VARCHAR(100) NOT NULL, -- ej: es-MX-DaliaNeural
  idioma VARCHAR(10) NOT NULL, -- es-MX, es-CO, es-ES
  configuracion JSONB, -- settings como rate, pitch, style
  activo BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(proveedor, codigo_voz)
);

-- Insertar voces por defecto (Azure)
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion)
VALUES 
  ('azure', 'es-MX-DaliaNeural', 'es-MX', '{"rate": "medium", "pitch": "+0st"}'),
  ('azure', 'es-CO-SalomeNeural', 'es-CO', '{"rate": "medium", "pitch": "+0st"}'),
  ('azure', 'es-ES-ElviraNeural', 'es-ES', '{"rate": "medium", "pitch": "+0st"}')
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;

-- Tabla de audios generados (cache por voz + segmento)
CREATE TABLE IF NOT EXISTS tbl_audios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id UUID NOT NULL REFERENCES tbl_documentos(id) ON DELETE CASCADE,
  segmento_id UUID NOT NULL REFERENCES tbl_segmentos(id) ON DELETE CASCADE,
  voz_id UUID NOT NULL REFERENCES tbl_voces(id) ON DELETE CASCADE,
  audio_url TEXT NOT NULL, -- URL en Supabase Storage
  duracion_ms INTEGER, -- duración en milisegundos
  sample_rate INTEGER DEFAULT 24000,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_access_at TIMESTAMP WITH TIME ZONE, -- Última vez que se accedió (para LRU)
  access_count INTEGER DEFAULT 0, -- Contador de accesos
  UNIQUE(documento_id, segmento_id, voz_id)
);

-- Índice para búsqueda rápida de audios por documento y voz
CREATE INDEX IF NOT EXISTS idx_audios_doc_voz ON tbl_audios(documento_id, voz_id);

-- Índice para limpieza LRU (ordenar por último acceso)
CREATE INDEX IF NOT EXISTS idx_audios_lru ON tbl_audios(last_access_at ASC NULLS FIRST);

-- Tabla de progreso de reproducción por usuario
CREATE TABLE IF NOT EXISTS tbl_progreso (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id UUID NOT NULL, -- TODO: integrar con auth real
  documento_id UUID NOT NULL REFERENCES tbl_documentos(id) ON DELETE CASCADE,
  voz_id UUID NOT NULL REFERENCES tbl_voces(id) ON DELETE CASCADE,
  segmento_id UUID NOT NULL REFERENCES tbl_segmentos(id) ON DELETE SET NULL,
  intra_ms INTEGER DEFAULT 0, -- posición dentro del segmento
  offset_global_char INTEGER, -- offset de carácter global (opcional)
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(usuario_id, documento_id, voz_id)
);

-- Índice para obtener progreso de un usuario
CREATE INDEX IF NOT EXISTS idx_progreso_usuario ON tbl_progreso(usuario_id, documento_id);

-- Comentarios para documentación
COMMENT ON TABLE tbl_documentos IS 'Documentos procesados para TTS con estado y hash de texto';
COMMENT ON TABLE tbl_segmentos IS 'Chunks de texto de ~1500 caracteres para síntesis TTS';
COMMENT ON TABLE tbl_voces IS 'Voces TTS disponibles de diferentes proveedores';
COMMENT ON TABLE tbl_audios IS 'Cache de audios generados por segmento y voz';
COMMENT ON TABLE tbl_progreso IS 'Progreso de reproducción por usuario, documento y voz';
