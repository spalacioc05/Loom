-- Índices para optimizar consultas de audios TTS
-- Ejecutar estos comandos en PostgreSQL para mejorar el rendimiento

-- Índice para buscar documentos por libro_id (consulta frecuente)
CREATE INDEX IF NOT EXISTS idx_documentos_libro_id 
ON tbl_documentos(libro_id);

-- Índice para buscar segmentos por documento_id (consulta muy frecuente)
CREATE INDEX IF NOT EXISTS idx_segmentos_documento_id 
ON tbl_segmentos(documento_id, orden);

-- Índice para buscar audios por segmento y voz (consulta crítica)
CREATE INDEX IF NOT EXISTS idx_audios_segmento_voz 
ON tbl_audios(segmento_id, voz_id);

-- Índice para buscar audios por documento y voz
CREATE INDEX IF NOT EXISTS idx_audios_documento_voz 
ON tbl_audios(documento_id, voz_id);

-- Índice para voces activas
CREATE INDEX IF NOT EXISTS idx_voces_activo 
ON tbl_voces(activo) WHERE activo = true;

-- Índice para progreso de usuario
CREATE INDEX IF NOT EXISTS idx_progreso_usuario_doc 
ON tbl_progreso(usuario_id, documento_id, voz_id);

-- Mostrar resultado
SELECT 
    'Índices creados exitosamente' as mensaje,
    COUNT(*) as total_indices
FROM pg_indexes 
WHERE schemaname = 'public' 
  AND tablename IN ('tbl_documentos', 'tbl_segmentos', 'tbl_audios', 'tbl_voces', 'tbl_progreso');
