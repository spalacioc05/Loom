-- Agregar más voces en español de Azure TTS
-- Voces mexicanas, españolas, colombianas, argentinas

-- 1. Voces Mexicanas (ya existe DaliaNeural)
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  ('azure', 'es-MX-JorgeNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-BeatrizNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-CandelaNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-CarlotaNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-LibertoNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-LucianoNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-MarinaNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-NuriaNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-PelayoNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-RenataNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-MX-YagoNeural', 'es-MX', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;

-- 2. Voces de España
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  ('azure', 'es-ES-ElviraNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-AlvaroNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-AbrilNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-ArnauNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-DarioNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-EliasNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-EstrellaNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-IreneNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-LaiaNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-LiaNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-NilNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-SaulNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-TeoNeural', 'es-ES', '{"rate": "0%", "pitch": "0%"}', true),
  ('azure', 'es-ES-TrianaNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-ES-VeraNeural', 'es-ES', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;

-- 3. Voces de Colombia
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  ('azure', 'es-CO-SalomeNeural', 'es-CO', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-CO-GonzaloNeural', 'es-CO', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;

-- 4. Voces de Argentina
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  ('azure', 'es-AR-ElenaNeural', 'es-AR', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-AR-TomasNeural', 'es-AR', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;

-- 5. Otras voces latinoamericanas
INSERT INTO tbl_voces (proveedor, codigo_voz, idioma, configuracion, activo)
VALUES 
  ('azure', 'es-CL-CatalinaNeural', 'es-CL', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-CL-LorenzoNeural', 'es-CL', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-PE-CamilaNeural', 'es-PE', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-PE-AlexNeural', 'es-PE', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-VE-PaolaNeural', 'es-VE', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true),
  ('azure', 'es-VE-SebastianNeural', 'es-VE', '{"rate": "0%", "pitch": "0%", "volume": "0%"}', true)
ON CONFLICT (proveedor, codigo_voz) DO NOTHING;
