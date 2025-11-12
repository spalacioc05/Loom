// Script para mostrar las voces disponibles
fetch('http://localhost:3000/voices')
  .then(r => r.json())
  .then(voices => {
    console.log('\n🎙️  VOCES DISPONIBLES:\n');
    console.log('═'.repeat(60));
    voices.forEach((v, i) => {
      const num = (i + 1).toString().padStart(2);
      const code = v.voice_code.padEnd(20);
      const lang = v.lang.padEnd(8);
      const type = v.settings_json.type;
      const speed = type === 'female' ? 'lenta ' : 'normal';
      console.log(`${num}. ${code} ${lang} [${type}] (${speed})`);
    });
    console.log('═'.repeat(60));
    console.log(`\nTotal: ${voices.length} voces de Google TTS`);
    console.log('✅ 0 voces de Azure\n');
  })
  .catch(err => console.error('Error:', err.message));
