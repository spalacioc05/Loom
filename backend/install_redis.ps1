# Script para instalar Redis usando Docker (la forma mas facil en Windows)

Write-Host ""
Write-Host "=== INSTALACION DE REDIS PARA LOOM ===" -ForegroundColor Cyan
Write-Host ""

# Verificar si Docker esta instalado
Write-Host "1. Verificando Docker..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version
    Write-Host "   OK Docker encontrado: $dockerVersion" -ForegroundColor Green
}
catch {
    Write-Host "   ERROR Docker no esta instalado" -ForegroundColor Red
    Write-Host ""
    Write-Host "Por favor instala Docker Desktop desde:" -ForegroundColor Yellow
    Write-Host "https://www.docker.com/products/docker-desktop" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Despues de instalar Docker, vuelve a ejecutar este script." -ForegroundColor Yellow
    exit 1
}

# Verificar si ya existe el contenedor
Write-Host ""
Write-Host "2. Verificando si Redis ya esta instalado..." -ForegroundColor Yellow
$existingContainer = docker ps -a --filter "name=redis-loom" --format "{{.Names}}"

if ($existingContainer -eq "redis-loom") {
    Write-Host "   INFO Redis ya esta instalado" -ForegroundColor Cyan
    
    # Verificar si esta corriendo
    $running = docker ps --filter "name=redis-loom" --format "{{.Names}}"
    
    if ($running -eq "redis-loom") {
        Write-Host "   OK Redis ya esta corriendo" -ForegroundColor Green
    }
    else {
        Write-Host "   AVISO Redis esta detenido, iniciando..." -ForegroundColor Yellow
        docker start redis-loom
        Start-Sleep -Seconds 2
        Write-Host "   OK Redis iniciado" -ForegroundColor Green
    }
}
else {
    Write-Host "   Descargando e instalando Redis..." -ForegroundColor Yellow
    docker run -d --name redis-loom -p 6379:6379 --restart unless-stopped redis:latest
    
    Start-Sleep -Seconds 3
    Write-Host "   OK Redis instalado y corriendo" -ForegroundColor Green
}

# Verificar conexion
Write-Host ""
Write-Host "3. Verificando conexion..." -ForegroundColor Yellow
try {
    $pingResult = docker exec redis-loom redis-cli ping
    if ($pingResult -eq "PONG") {
        Write-Host "   OK Conexion exitosa (PONG recibido)" -ForegroundColor Green
    }
    else {
        Write-Host "   AVISO Respuesta inesperada: $pingResult" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "   ERROR No se pudo conectar a Redis" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Red
    exit 1
}

# Mostrar informacion
Write-Host ""
Write-Host "=== REDIS CONFIGURADO EXITOSAMENTE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Informacion de Redis:" -ForegroundColor Cyan
Write-Host "   Host: localhost" -ForegroundColor White
Write-Host "   Port: 6379" -ForegroundColor White
Write-Host "   Contenedor: redis-loom" -ForegroundColor White
Write-Host ""

Write-Host "Comandos utiles:" -ForegroundColor Cyan
Write-Host "   Ver estado:        docker ps -a | Select-String redis-loom" -ForegroundColor White
Write-Host "   Detener:           docker stop redis-loom" -ForegroundColor White
Write-Host "   Iniciar:           docker start redis-loom" -ForegroundColor White
Write-Host "   Ver logs:          docker logs redis-loom" -ForegroundColor White
Write-Host "   Conectar CLI:      docker exec -it redis-loom redis-cli" -ForegroundColor White
Write-Host "   Eliminar:          docker rm -f redis-loom" -ForegroundColor White
Write-Host ""

Write-Host "Proximo paso:" -ForegroundColor Yellow
Write-Host "   Inicia el backend normalmente con:" -ForegroundColor White
Write-Host "   node index.js" -ForegroundColor Cyan
Write-Host ""
Write-Host "   El backend detectara Redis automaticamente y mostrara:" -ForegroundColor White
Write-Host "   [Redis Cache] OK Listo y operacional" -ForegroundColor Green
Write-Host ""
