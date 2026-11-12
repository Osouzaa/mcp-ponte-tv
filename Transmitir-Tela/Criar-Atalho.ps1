# Criar-Atalho.ps1 - cria o atalho "Transmitir Tela" na area de trabalho deste computador.
# Uso: de duplo clique em "Criar-Atalho.bat". Nao precisa ser administrador.
# Obs.: so ASCII neste arquivo de proposito (evita erro de acentos no PowerShell 5.1).
$ErrorActionPreference = "Stop"
$alvo = Join-Path $PSScriptRoot "Transmitir-Tela.bat"
if (-not (Test-Path $alvo)) { Write-Host "Nao encontrei Transmitir-Tela.bat ao lado deste script." -ForegroundColor Yellow; Read-Host "Pressione Enter para fechar" | Out-Null; exit 1 }
$desktop = [Environment]::GetFolderPath("Desktop")   # respeita area de trabalho redirecionada (OneDrive)
$lnkPath = Join-Path $desktop "Transmitir Tela.lnk"
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
$lnk.TargetPath = $alvo
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.WindowStyle = 1
$lnk.Description = "Transmitir a minha tela para a TV"
$lnk.IconLocation = "shell32.dll,18"
$lnk.Save()
Write-Host "Atalho criado: $lnkPath" -ForegroundColor Green
Write-Host "Obs.: se voce mover ou apagar esta pasta, o atalho deixa de funcionar (rode este script de novo)."
Start-Sleep 3
