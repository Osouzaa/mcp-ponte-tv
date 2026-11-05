# Copie este arquivo para "config.local.ps1" (ao lado dos scripts) e preencha com os valores da SUA rede.
# O config.local.ps1 NAO vai para o Git (esta no .gitignore). Nao coloque dados reais neste arquivo de exemplo.

$Ponte          = "192.0.2.10"        # IP da maquina-ponte (a que fica ligada a TV por HDMI)
$TvEndereco     = "192.0.2.20:5555"   # IP:porta da TV Android (ADB) - so para os scripts/MCP de TV Android
$FaixaLiberada  = "192.0.2.0/24"      # quem pode enviar video para a ponte (IPs ou faixas CIDR) - usado ao instalar a ponte
