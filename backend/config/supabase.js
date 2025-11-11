import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

const supabaseUrl = process.env.SUPABASE_URL || 'https://yditubxizgubcntiysnh.supabase.co';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkaXR1Ynhpemd1YmNudGl5c25oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2ODEzMDQsImV4cCI6MjA3NjI1NzMwNH0.6PPAFfuGoIpoGDCsNc1d98AkArU3oPXAw2y448rukm4';

export const supabase = createClient(supabaseUrl, supabaseKey);

