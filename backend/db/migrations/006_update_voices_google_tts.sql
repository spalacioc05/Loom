-- Migración 006: Actualizar voces para usar Google TTS (proveedor gratuito)
-- Eliminar todas las voces de Azure y agregar voces de Google TTS

-- 1. Eliminar completamente todas las voces de Azure
-- Nota: CASCADE eliminará también referencias en tbl_audios si las hay
DELETE FROM tbl_voces 
WHERE proveedor = 'azure';

-- 2. Insertar voces de Google TTS gratuito
-- Google TTS soporta variantes limitadas de idiomas: es, en, fr, de, it, pt, etc.
-- Agregamos voces en español con códigos descriptivos

-- Voces Femeninas en Español
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  ('google', 'es-Female-1', 'es', '{"rate": "1.0", "pitch": "0", "type": "female"}', true),
  ('google', 'es-Female-2', 'es', '{"rate": "1.0", "pitch": "0", "type": "female"}', true),
  ('google', 'es-MX-Female', 'es-MX', '{"rate": "1.0", "pitch": "0", "type": "female"}', true),
  ('google', 'es-ES-Female', 'es-ES', '{"rate": "1.0", "pitch": "0", "type": "female"}', true),
  ('google', 'es-AR-Female', 'es-AR', '{"rate": "1.0", "pitch": "0", "type": "female"}', true),
  ('google', 'es-CO-Female', 'es-CO', '{"rate": "1.0", "pitch": "0", "type": "female"}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;

-- Voces Masculinas en Español
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  ('google', 'es-Male-1', 'es', '{"rate": "1.0", "pitch": "0", "type": "male"}', true),
  ('google', 'es-Male-2', 'es', '{"rate": "1.0", "pitch": "0", "type": "male"}', true),
  ('google', 'es-MX-Male', 'es-MX', '{"rate": "1.0", "pitch": "0", "type": "male"}', true),
  ('google', 'es-ES-Male', 'es-ES', '{"rate": "1.0", "pitch": "0", "type": "male"}', true),
  ('google', 'es-AR-Male', 'es-AR', '{"rate": "1.0", "pitch": "0", "type": "male"}', true),
  ('google', 'es-CO-Male', 'es-CO', '{"rate": "1.0", "pitch": "0", "type": "male"}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;

-- NOTA: Google TTS no diferencia realmente entre acentos (MX, ES, AR, CO).
-- Todas las variantes mapean a 'es' en el API de Google Translate TTS.
-- Los códigos descriptivos son para la UI del usuario únicamente.
