# mcp-tv-cast

Ferramentas para **mostrar a tela do PC (Windows) numa TV** com pouco atraso, sem depender do Win + K.

*English: tools to mirror a Windows PC screen to a TV with low latency. A "bridge" PC connected to the TV by HDMI receives
the video over UDP (FFmpeg → ffplay); plus an MCP server to control Android TV / Samsung TVs.*

O projeto tem duas partes independentes:

| Parte | Para quê |
|---|---|
| **Ponte de tela** (scripts PowerShell) | Um PC ligado à TV por HDMI recebe a tela de outros PCs pela rede e a exibe em tela cheia, com tela de espera. |
| **Servidor MCP** (`src/index.ts`) | Ferramentas para um assistente (Claude etc.) controlar TVs: Miracast, Samsung (Tizen) e Android TV por ADB. |

---

## 1. Ponte de tela

```
PC de origem ── FFmpeg (captura + encoder de hardware) ──UDP──▶ PC-ponte ── ffplay em tela cheia ──HDMI──▶ TV
```

Por que assim: TVs baratas decodificam vídeo mal e o Miracast (Wi-Fi Direct) costuma falhar. Com um PC de verdade na ponta
o atraso fica pequeno, e o UDP não forma fila: o que não dá para exibir é descartado.

### Requisitos
- Windows 10/11 nos dois PCs, na mesma rede. `winget` disponível (para instalar o FFmpeg).
- Origem: GPU Intel (QSV), NVIDIA ou AMD para o encoder de hardware (há *fallback* por software).
- Ponte: acesso de **administrador** (para a regra de firewall) apenas na instalação.

### Configuração
Copie `config.exemplo.ps1` para `config.local.ps1` e preencha com os valores da sua rede. Esse arquivo **não é versionado**.

```powershell
$Ponte         = "192.0.2.10"      # IP da máquina-ponte
$FaixaLiberada = "192.0.2.0/24"    # quem pode enviar vídeo para a ponte
```

### Instalar a ponte (uma vez, como administrador, na máquina-ponte)
```powershell
powershell -ExecutionPolicy Bypass -File .\receber-tela-ponte.ps1 -IniciarComWindows
```
Instala o FFmpeg, libera **UDP 5004 apenas para a faixa informada**, grava o receptor e cria o atalho "Receber tela".
Quando ninguém transmite, a TV mostra uma **tela de espera** (nome, relógio, data, passos); ao começar a transmissão ela
vira vídeo sozinha e, ao parar, volta para a espera. O visual fica em `tema.json` (nome, cores, logos) e pode ser aplicado com `-TemaJson`.
Veja `tema.exemplo.json`. Outras opções: `-AdicionarIp`, `-Remover` (cabeçalho do script).

### Transmitir
- `Transmitir-Tela\Transmitir-Tela.bat`: duplo clique, escolhe a tela e a qualidade (para quem só usa).
- `espelhar-ponte.ps1 -Tela 1|2|3`: uso direto, 1080p/60 fps por padrão.

> A numeração das telas segue a ordem de captura do Windows (DXGI), que pode diferir da numeração do painel de vídeo.
> Se aparecer a tela errada, tente outro número.

### Limitações
- Sem áudio. Uma pessoa por vez.
- O vídeo vai **sem criptografia** pela rede local (veja Segurança).

### Pauta e reuniões na tela de espera
A tela de espera pode mostrar a **agenda do dia**, com `AGORA` e `EM SEGUIDA`, e um aviso. Na ponte, edite
`C:\ProgramData\ReceberTela\pauta.json` (formato em `pauta.exemplo.json`). O receptor recarrega sozinho em ~20 s, sem reiniciar.
Cada item tem `inicio` e `fim` (`HH:mm`), `titulo` e `local`; `data` (`AAAA-MM-DD`) é opcional (sem ela, o item vale todo dia).
Mostra até 5 itens, os já encerrados ficam esmaecidos. Sem itens nem aviso, a tela volta ao layout centralizado.

Projetos: `projetos` com `nome`, `percentual` (0-100), `responsavel`, `prazo` e `situacao` (`no prazo`, `atenção`, `atrasado`, `concluído`). Quando há agenda e projetos, o cartão da direita alterna entre os dois a cada 12 s.
### Tarefas da equipe (lateral direita)
Com `tarefas` no `pauta.json`, a tela de espera ganha uma coluna fixa na lateral direita; agenda e projetos continuam alternando
no centro. Sem agenda/projetos, as tarefas ocupam a coluna da direita sozinhas. Cada tarefa tem `titulo`, `responsavel`, `prazo`
(texto livre, ex. `14/11`), `status` (`a fazer`, `em andamento`, `bloqueada`, `concluída`) e, opcional, `prioridade: "alta"`.
Ordem na tela: bloqueadas, em andamento, a fazer. **As concluídas ficam ocultas** (a barra de progresso ainda conta com elas); para mostrá-las, ponha `"mostrarConcluidas": true` no `pauta.json`. Mostra 6 por vez e troca de página a cada 10 s.
O título do painel vem de `tituloTarefas`. Exemplo completo em `pauta.exemplo.json`.

### Tarefas ligadas ao Jira Cloud
As tarefas da lateral direita podem vir de um **quadro (board) do Jira Cloud**, atualizadas a cada 15 s (a tarefa agendada roda a cada 1 min e busca 4 vezes dentro dele). O card mostra "Atualizado dd/MM HH:mm" e, se o Jira ficar mais de 10 min sem atualizar, avisa em amarelo "Sem atualizar desde ...". Na ponte, rode `Configurar-Jira.bat`
uma vez (usuário que fica logado, sem administrador): ele pede site (`https://empresa.atlassian.net`), e-mail, **API token**
([criar aqui](https://id.atlassian.com/manage-profile/security/api-tokens)) e o número do quadro (na URL `.../boards/NUMERO`), testa a conexão
e cria a tarefa agendada `ReceberTela-Jira`. O token fica protegido pelo Windows em `%APPDATA%\ReceberTela\jira.json` (só aquele usuário lê).
- Quadro Scrum: mostra as issues do **sprint ativo**; Kanban: as issues não concluídas do quadro.
- Mapeamento: categoria de status `Done` → concluída; `In Progress` → em andamento; `To Do` → a fazer; status/label com "bloq"/"impedido"/`blocked` → bloqueada;
  prioridade Highest/High → selo ALTA; `duedate` → prazo; responsável = primeiro nome. A chave (ex. `GES-12`) aparece junto.
- `Sincronizar-Jira.ps1 -Mostrar` testa na hora; log em `%APPDATA%\ReceberTela\jira-sync.log`. Se o Jira ficar fora do ar, a TV mantém a última lista.
- Com o Jira configurado, ele tem prioridade sobre `tarefas` do `pauta.json`. Para desligar: `Configurar-Jira.ps1 -Remover`.

### Imagem quebrando? Diagnóstico
- A ponte grava `C:\ProgramData\ReceberTela\qualidade.log`: uma linha por transmissão, com IP do emissor, duração e **% de pacotes perdidos**
  (medido pelo contador de continuidade do MPEG-TS). Perda acima de ~0,1% já aparece como imagem quebrada. Isso mostra **quais PCs** têm problema:
  geralmente Wi-Fi, ou cabo/switch ruim naquele ponto.
- A ponte aceita **um emissor por vez**: enquanto um PC transmite, pacotes de outro IP são descartados (antes as imagens se misturavam
  se alguém esquecesse a transmissão aberta). O número de pacotes descartados também vai para o log.
- Quem transmite: quadro-chave a cada 0,5 s (recupera rápido após uma perda), IDR forçado, taxa limitada a 6 Mbps no Wi-Fi, e
  queda automática para 720p/30 quando o PC não tem encoder de vídeo na placa (software em 1080p estoura a CPU). O teste de encoder agora usa a resolução escolhida.
  O log do FFmpeg fica em `%TEMP%\transmitir-tela.log`.
- Para reaplicar na ponte, rode de novo `receber-tela-ponte.ps1` (como administrador): ele regrava o receptor e preserva `tema.json` e `pauta.json`.

## 2. Servidor MCP

```powershell
npm install
npm run build
npm run inspect          # opcional: testar no MCP Inspector
claude mcp add tv-cast -- node C:\caminho\mcp-tv-cast\dist\index.js
```

| Ferramenta | O que faz |
|---|---|
| `diagnosticar_miracast`, `listar_displays_sem_fio`, `abrir_painel_transmitir`, `modo_projecao` | Apoio ao Miracast / Win + K / Win + P |
| `ligar_tv`, `samsung_tecla` | Wake-on-LAN e controle de TV Samsung (Tizen) |
| `instalar_ferramentas` | Instala adb e scrcpy via winget |
| `tv_conectar`, `tv_dispositivos`, `tv_info`, `tv_listar_apps` | Android TV por ADB: conexão e diagnóstico |
| `tv_otimizar`, `tv_reativar_app` | Limpa cache, reduz animações, desativa apps (reversível) |
| `tv_tecla`, `tv_abrir_app`, `tv_reiniciar`, `tv_miracast_receber`, `tv_espelhar` | Controle remoto, receptor Miracast e espelhamento com scrcpy |

Variáveis opcionais: `ADB_PATH`, `SCRCPY_PATH`. Android TV: ative *Depuração USB/ADB* e *Depuração de rede* nas opções do desenvolvedor.

## Segurança
- Este repositório **não contém** IPs, nomes de máquina, senhas ou logos. Tudo isso fica em arquivos locais ignorados pelo Git
  (`config.local.ps1`, `tema.local.json`, `logos/`). Não os envie.
- A ponte só aceita UDP da faixa que você definir. O filtro é por IP, **sem autenticação nem criptografia**:
  qualquer máquina dessa faixa pode enviar imagem para a TV, e o vídeo pode ser visto por quem capturar o tráfego da rede.
  Use em redes confiáveis e peça autorização ao responsável pela rede antes de instalar.
- O MCP executa comandos (adb, PowerShell) no seu PC: use somente com assistentes e TVs em que você confia.

## Licença
MIT, veja `LICENSE`.
#   m c p - p o n t e - t v  
 

