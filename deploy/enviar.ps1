<#
.SYNOPSIS
Envia uma pasta de álbum para o bucket S3 do SeaweedFS e dispara o scan do Polaris.

.EXAMPLE
./deploy/enviar.ps1 "D:\Musicas\Artista\Album"

.EXAMPLE
./deploy/enviar.ps1 "D:\Downloads\album-x" -Destino "Artista/Album"
#>
param(
	[Parameter(Mandatory)]
	[string]$Origem,
	# Bucket path; defaults to the last two folders of $Origem (Artista/Album).
	[string]$Destino,
	[string]$Remote = "mymusic"
)

$ErrorActionPreference = "Stop"

foreach ($name in "POLARIS_URL", "POLARIS_USER", "POLARIS_PASSWORD") {
	if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Variável de ambiente $name não definida." }
}

$pasta = Get-Item -LiteralPath $Origem
if (-not $pasta.PSIsContainer) { throw "Origem precisa ser uma pasta: $Origem" }

if (-not $Destino) { $Destino = "$($pasta.Parent.Name)/$($pasta.Name)" }

rclone copy $pasta.FullName "${Remote}:music/$Destino" --progress
if ($LASTEXITCODE -ne 0) { throw "rclone falhou (código $LASTEXITCODE)." }

$api = $env:POLARIS_URL.TrimEnd("/") + "/api"
$credenciais = @{ username = $env:POLARIS_USER; password = $env:POLARIS_PASSWORD } | ConvertTo-Json
$auth = Invoke-RestMethod -Method Post -Uri "$api/auth" -ContentType "application/json" -Body $credenciais
Invoke-RestMethod -Method Post -Uri "$api/trigger_index" -Headers @{ Authorization = "Bearer $($auth.token)" } | Out-Null

Write-Host "Enviado para music/$Destino. Scan do Polaris disparado."
