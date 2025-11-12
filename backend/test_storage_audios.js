import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

async function main() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
  }
  const supabase = createClient(url, key);

  console.log('Listing buckets...');
  const { data: buckets, error: listErr } = await supabase.storage.listBuckets();
  if (listErr) {
    console.error('listBuckets error:', listErr);
    process.exit(1);
  }
  const names = buckets.map(b => b.name);
  console.log('Buckets:', names.join(', '));

  if (!names.includes('audios_tts')) {
    console.log('Bucket audios_tts not found. Creating (public=true)...');
    const { data: created, error: createErr } = await supabase.storage.createBucket('audios_tts', { public: true });
    if (createErr) {
      console.error('createBucket error:', createErr);
      process.exit(1);
    }
    console.log('Created bucket audios_tts:', created?.name || 'ok');
  } else {
    console.log('Bucket audios_tts exists.');
  }

  // Try upload a small test file
  const path = 'diagnostics/ping.txt';
  const bytes = new TextEncoder().encode('ok ' + new Date().toISOString());
  console.log('Uploading test object:', path);
  const { data: up, error: upErr } = await supabase.storage
    .from('audios_tts')
    .upload(path, bytes, { contentType: 'text/plain', upsert: true });
  if (upErr) {
    console.error('Upload error:', upErr);
    process.exit(1);
  }
  console.log('Upload ok:', up?.path || path);

  const { data: urlData } = supabase.storage.from('audios_tts').getPublicUrl(path);
  console.log('Public URL:', urlData.publicUrl);
  console.log('✅ Storage diagnostics finished.');
}

main().catch(e => { console.error(e); process.exit(1); });
