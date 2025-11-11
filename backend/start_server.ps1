# Script para mantener el backend corriendo
# Se reinicia automáticamente si se cae

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  Iniciando Backend - Servicio TTS" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

while ($true) {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iniciando servidor..." -ForegroundColor Green
    
    # Ejecutar node y capturar el código de salida
    node index.js
    
    $exitCode = $LASTEXITCODE
    
    Write-Host ""
    Write-Host "====================================" -ForegroundColor Yellow
    Write-Host "  El servidor se detuvo (Exit: $exitCode)" -ForegroundColor Yellow
    Write-Host "====================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Si fue Ctrl+C (exit code 3221225786 en Windows), salir
    if ($exitCode -eq 3221225786 -or $exitCode -eq 130) {
        Write-Host "Servidor detenido por el usuario. Saliendo..." -ForegroundColor Red
        break
    }
    
    Write-Host "Reiniciando en 3 segundos... (Ctrl+C para cancelar)" -ForegroundColor Cyan
    Start-Sleep -Seconds 3
}
