# Script para configurar el Firewall de Windows para el backend Node.js
# Ejecutar como Administrador (botón derecho -> Ejecutar como administrador)

Write-Host "🔥 Configurando Firewall de Windows..." -ForegroundColor Cyan

# Verificar si ya existe la regla
$existingRule = Get-NetFirewallRule -DisplayName "Node.js Backend (Port 3000)" -ErrorAction SilentlyContinue

if ($existingRule) {
    Write-Host "⚠️  La regla ya existe. Eliminando regla anterior..." -ForegroundColor Yellow
    Remove-NetFirewallRule -DisplayName "Node.js Backend (Port 3000)"
}

# Crear nueva regla de firewall
New-NetFirewallRule `
    -DisplayName "Node.js Backend (Port 3000)" `
    -Description "Permite conexiones entrantes al backend Node.js en puerto 3000" `
    -Direction Inbound `
    -LocalPort 3000 `
    -Protocol TCP `
    -Action Allow `
    -Profile Any `
    -Enabled True

Write-Host "✅ Firewall configurado correctamente!" -ForegroundColor Green
Write-Host "   - Puerto 3000 ahora acepta conexiones desde tu celular" -ForegroundColor Green
Write-Host "   - Tu IP actual del backend: http://10.120.227.214:3000" -ForegroundColor Cyan

# Mostrar información de red
Write-Host "`n📡 Información de red:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp | Select-Object IPAddress, InterfaceAlias | Format-Table

Write-Host "`nPresiona cualquier tecla para cerrar..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
