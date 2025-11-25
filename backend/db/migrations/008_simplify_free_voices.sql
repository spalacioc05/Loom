-- Migración 008: Simplificar voces gratuitas a solo 2 opciones reales
-- Google TTS gratuito solo ofrece 2 variantes: normal y slow (lenta/clara)

-- 1. Eliminar todas las voces de Google TTS anteriores
DELETE FROM tbl_voces 
WHERE proveedor = 'google';

-- 2. Insertar voces reales que Google TTS soporta (español e inglés)
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  -- Español
  ('google', 'es-Normal', 'es', '{"rate": "1.0", "pitch": "0", "slow": false}', true),
  ('google', 'es-Clara', 'es', '{"rate": "1.0", "pitch": "0", "slow": true}', true),
  -- Inglés
  ('google', 'en-Normal', 'en', '{"rate": "1.0", "pitch": "0", "slow": false}', true),
  ('google', 'en-Clear', 'en', '{"rate": "1.0", "pitch": "0", "slow": true}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;

-- NOTA: Google TTS gratuito (google-tts-api) solo tiene 2 parámetros:
-- - lang: idioma (es, en, fr, etc.)
-- - slow: false (voz normal) o true (voz lenta/clara)
-- No soporta múltiples voces, acentos, ni pitch/gender diferentes.
