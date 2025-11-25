#!/usr/bin/env node

// Script de verificación pre-despliegue
// Verifica que todo esté listo para Render

import { existsSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const rootDir = join(__dirname, '..');

console.log('🔍 VERIFICACIÓN PRE-DESPLIEGUE\n');

let allOk = true;
const errors = [];
const warnings = [];

// 1. Verificar archivos esenciales
console.log('📁 Verificando archivos...');
const requiredFiles = [
  'render.yaml',
  'backend/package.json',
  'backend/index.js',
  'backend/services/redis_cache.js',
  '.gitignore',
];

for (const file of requiredFiles) {
  const filePath = join(rootDir, file);
  if (existsSync(filePath)) {
    console.log(`  ✅ ${file}`);
  } else {
    console.log(`  ❌ ${file} NO EXISTE`);
    errors.push(`Archivo faltante: ${file}`);
    allOk = false;
  }
}

// 2. Verificar package.json
console.log('\n📦 Verificando package.json...');
try {
  const pkgPath = join(rootDir, 'backend/package.json');
  const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
  
  // Verificar scripts
  if (pkg.scripts && pkg.scripts.start) {
    console.log(`  ✅ Script "start" definido: ${pkg.scripts.start}`);
  } else {
    console.log(`  ❌ Script "start" NO definido`);
    errors.push('package.json debe tener "start": "node index.js"');
    allOk = false;
  }
  
  // Verificar dependencias críticas
  const requiredDeps = ['express', 'ioredis', 'pg', '@supabase/supabase-js'];
  for (const dep of requiredDeps) {
    if (pkg.dependencies && pkg.dependencies[dep]) {
      console.log(`  ✅ ${dep}: ${pkg.dependencies[dep]}`);
    } else {
      console.log(`  ❌ ${dep} NO instalado`);
      errors.push(`Dependencia faltante: ${dep}`);
      allOk = false;
    }
  }
} catch (e) {
  console.log(`  ❌ Error leyendo package.json: ${e.message}`);
  errors.push('No se pudo leer package.json');
  allOk = false;
}

// 3. Verificar render.yaml
console.log('\n📄 Verificando render.yaml...');
try {
  const renderYaml = readFileSync(join(rootDir, 'render.yaml'), 'utf8');
  
  if (renderYaml.includes('loom-backend')) {
    console.log('  ✅ Servicio backend configurado');
  } else {
    console.log('  ❌ Servicio backend NO encontrado');
    errors.push('render.yaml debe definir loom-backend');
    allOk = false;
  }
  
  if (renderYaml.includes('loom-redis')) {
    console.log('  ✅ Redis configurado');
  } else {
    console.log('  ❌ Redis NO encontrado');
    errors.push('render.yaml debe definir loom-redis');
    allOk = false;
  }
  
  if (renderYaml.includes('REDIS_URL')) {
    console.log('  ✅ Variable REDIS_URL conectada');
  } else {
    console.log('  ⚠️ REDIS_URL no configurada en render.yaml');
    warnings.push('render.yaml debería conectar REDIS_URL desde loom-redis');
  }
} catch (e) {
  console.log(`  ❌ Error leyendo render.yaml: ${e.message}`);
  errors.push('No se pudo leer render.yaml');
  allOk = false;
}

// 4. Verificar .env (solo advertencia)
console.log('\n🔐 Verificando .env...');
const envPath = join(rootDir, 'backend/.env');
if (existsSync(envPath)) {
  console.log('  ✅ .env existe (para desarrollo local)');
  
  const envContent = readFileSync(envPath, 'utf8');
  const requiredEnvVars = ['DATABASE_URL', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'];
  
  for (const envVar of requiredEnvVars) {
    if (envContent.includes(envVar)) {
      console.log(`  ✅ ${envVar} definido`);
    } else {
      console.log(`  ⚠️ ${envVar} NO definido en .env`);
      warnings.push(`${envVar} debe configurarse en Render manualmente`);
    }
  }
} else {
  console.log('  ⚠️ .env NO existe (normal, se configura en Render)');
  warnings.push('Recuerda configurar variables de entorno en Render Dashboard');
}

// 5. Verificar .gitignore
console.log('\n🚫 Verificando .gitignore...');
try {
  const gitignorePath = join(rootDir, '.gitignore');
  if (existsSync(gitignorePath)) {
    const gitignore = readFileSync(gitignorePath, 'utf8');
    
    const shouldIgnore = ['node_modules', '.env', 'tmp'];
    for (const pattern of shouldIgnore) {
      if (gitignore.includes(pattern)) {
        console.log(`  ✅ ${pattern} ignorado`);
      } else {
        console.log(`  ⚠️ ${pattern} NO está en .gitignore`);
        warnings.push(`Agrega ${pattern} a .gitignore`);
      }
    }
  } else {
    console.log('  ⚠️ .gitignore NO existe');
    warnings.push('Crea .gitignore para evitar subir archivos sensibles');
  }
} catch (e) {
  console.log(`  ⚠️ Error leyendo .gitignore: ${e.message}`);
}

// 6. Verificar git
console.log('\n📌 Verificando Git...');
if (existsSync(join(rootDir, '.git'))) {
  console.log('  ✅ Repositorio Git inicializado');
} else {
  console.log('  ❌ NO es un repositorio Git');
  errors.push('Ejecuta: git init');
  allOk = false;
}

// RESUMEN
console.log('\n' + '='.repeat(50));
console.log('📊 RESUMEN\n');

if (errors.length > 0) {
  console.log('❌ ERRORES CRÍTICOS:');
  errors.forEach(err => console.log(`  • ${err}`));
  console.log('');
}

if (warnings.length > 0) {
  console.log('⚠️ ADVERTENCIAS:');
  warnings.forEach(warn => console.log(`  • ${warn}`));
  console.log('');
}

if (allOk && warnings.length === 0) {
  console.log('🎉 TODO LISTO PARA DESPLEGAR');
  console.log('\nPróximos pasos:');
  console.log('  1. git add .');
  console.log('  2. git commit -m "feat: Configuración Render"');
  console.log('  3. git push origin main');
  console.log('  4. Ir a https://render.com y crear Blueprint');
  process.exit(0);
} else if (allOk) {
  console.log('✅ Verificación APROBADA (con advertencias)');
  console.log('\nPuedes continuar con el despliegue, pero revisa las advertencias.');
  process.exit(0);
} else {
  console.log('❌ Verificación FALLIDA');
  console.log('\nCorrige los errores antes de desplegar.');
  process.exit(1);
}
