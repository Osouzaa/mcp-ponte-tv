#!/usr/bin/env node
/**
 * MCP "tv-cast" — ajuda a conectar o PC Windows a uma TV via Miracast (Win + K).
 *
 * Roda LOCALMENTE no Windows (transporte stdio). Ferramentas:
 *  - diagnosticar_miracast   → verifica se placa de vídeo + Wi-Fi suportam Miracast
 *  - listar_displays_sem_fio → lista TVs/receptores Miracast já pareados/detectados
 *  - abrir_painel_transmitir → abre o painel "Transmitir" (o mesmo do Win + K)
 *  - modo_projecao           → duplicar / estender / só PC / só segunda tela (Win + P)
 *  - ligar_tv                → Wake-on-LAN (TV precisa ter "ligar via rede" ativo)
 *  - samsung_tecla           → envia tecla para TV Samsung (ex.: KEY_SOURCE p/ espelhamento)
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import dgram from "node:dgram";
import WebSocket from "ws";

const run = promisify(execFile);

async function ps(script: string): Promise<string> {
  const { stdout, stderr } = await run(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script],
    { windowsHide: true, maxBuffer: 10 * 1024 * 1024 },
  );
  return (stdout || stderr).trim();
}

const text = (t: string) => ({ content: [{ type: "text" as const, text: t }] });
const fail = (e: unknown) => ({
  isError: true,
  content: [{ type: "text" as const, text: `Erro: ${e instanceof Error ? e.message : String(e)}` }],
});

const server = new McpServer({ name: "tv-cast", version: "0.1.0" });

// ---------------------------------------------------------------- PC (Windows)

server.registerTool(
  "diagnosticar_miracast",
  {
    description:
      "Verifica se o PC suporta Miracast (driver gráfico e Wi-Fi), status do Wi-Fi e do serviço de projeção.",
    inputSchema: {},
  },
  async () => {
    try {
      const drivers = await ps(
        "netsh wlan show drivers | Select-String -Pattern 'Wireless Display|Exibição sem fio|Driver|Radio|Rádio'",
      );
      const iface = await ps("netsh wlan show interfaces | Select-String -Pattern 'State|Estado|SSID|Band|Banda|Channel|Canal|Signal|Sinal'");
      const svc = await ps(
        "Get-Service -Name 'DevicesFlowUserSvc*','WFDSConMgrSvc' -ErrorAction SilentlyContinue | Format-Table Name,Status -AutoSize | Out-String",
      );
      return text(
        [
          "=== Driver Wi-Fi / Miracast ===",
          drivers || "(sem saída — Wi-Fi desligado ou sem adaptador)",
          "",
          "=== Interface Wi-Fi ===",
          iface,
          "",
          "=== Serviços ===",
          svc,
          "",
          "Dica: procure 'Wireless Display Supported: Graphics Driver: Yes  Wi-Fi Driver: Yes'.",
          "Se algum for 'No', atualize o driver da placa de vídeo/Wi-Fi. Miracast exige o Wi-Fi LIGADO,",
          "mesmo usando cabo de rede. Rede em 5 GHz e PC perto da TV reduzem travamentos.",
        ].join("\n"),
      );
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "listar_displays_sem_fio",
  {
    description: "Lista receptores Miracast / Wireless Display que o Windows conhece (pareados ou detectados).",
    inputSchema: {},
  },
  async () => {
    try {
      const out = await ps(
        "Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Miracast|Wireless Display|Monitor sem fio|TV|DMR' -or $_.Class -eq 'Display' } | " +
          "Select-Object Status, Class, FriendlyName | Format-Table -AutoSize | Out-String -Width 200",
      );
      return text(out || "Nenhum display sem fio encontrado. Ligue a TV no modo 'Espelhamento de tela' e use abrir_painel_transmitir.");
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "abrir_painel_transmitir",
  {
    description: "Abre o painel 'Transmitir' do Windows (equivalente a Win + K) para escolher a TV.",
    inputSchema: {},
  },
  async () => {
    try {
      // 1ª tentativa: URI oficial do painel de dispositivos conectáveis
      await ps("Start-Process 'ms-settings-connectabledevices:devicediscovery'");
      return text("Painel 'Transmitir' aberto. Selecione a TV na lista (ela precisa estar no modo de espelhamento).");
    } catch {
      try {
        // Fallback: simula Win + K
        await ps(`
Add-Type @"
using System; using System.Runtime.InteropServices;
public class K { [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, UIntPtr e); }
"@
[K]::keybd_event(0x5B,0,0,[UIntPtr]::Zero); [K]::keybd_event(0x4B,0,0,[UIntPtr]::Zero)
[K]::keybd_event(0x4B,0,2,[UIntPtr]::Zero); [K]::keybd_event(0x5B,0,2,[UIntPtr]::Zero)`);
        return text("Win + K enviado. Selecione a TV no painel.");
      } catch (e) {
        return fail(e);
      }
    }
  },
);

server.registerTool(
  "modo_projecao",
  {
    description: "Define como a tela vai para a TV (equivalente a Win + P).",
    inputSchema: {
      modo: z
        .enum(["duplicar", "estender", "somente_pc", "somente_segunda_tela"])
        .describe("duplicar = mesma imagem; estender = área de trabalho estendida"),
    },
  },
  async ({ modo }) => {
    const flag = { duplicar: "/clone", estender: "/extend", somente_pc: "/internal", somente_segunda_tela: "/external" }[modo];
    try {
      await run("DisplaySwitch.exe", [flag], { windowsHide: true });
      return text(`Modo de projeção alterado para: ${modo}`);
    } catch (e) {
      return fail(e);
    }
  },
);

// ---------------------------------------------------------------- TV

server.registerTool(
  "ligar_tv",
  {
    description: "Liga a TV via Wake-on-LAN (a TV precisa estar na mesma rede e com 'Ligar via Wi-Fi/rede' ativado).",
    inputSchema: {
      mac: z.string().regex(/^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/).describe("MAC da TV, ex.: AA:BB:CC:DD:EE:FF"),
      broadcast: z.string().default("255.255.255.255"),
    },
  },
  async ({ mac, broadcast }) => {
    const bytes = Buffer.from(mac.replace(/[:-]/g, ""), "hex");
    const packet = Buffer.concat([Buffer.alloc(6, 0xff), ...Array(16).fill(bytes)]);
    const sock = dgram.createSocket("udp4");
    try {
      await new Promise<void>((res, rej) => sock.bind(() => { sock.setBroadcast(true); res(); }).on("error", rej));
      for (const port of [9, 7]) {
        await new Promise<void>((res, rej) => sock.send(packet, port, broadcast, (err) => (err ? rej(err) : res())));
      }
      return text(`Pacote Wake-on-LAN enviado para ${mac}. Aguarde ~10 s antes de transmitir.`);
    } catch (e) {
      return fail(e);
    } finally {
      sock.close();
    }
  },
);

server.registerTool(
  "samsung_tecla",
  {
    description:
      "Envia uma tecla do controle para TV Samsung (Tizen) na rede. Use KEY_SOURCE para abrir as entradas/espelhamento. " +
      "Na primeira vez a TV pede para autorizar o dispositivo; guarde o token retornado.",
    inputSchema: {
      ip: z.string().describe("IP da TV"),
      tecla: z.string().default("KEY_SOURCE").describe("Ex.: KEY_SOURCE, KEY_POWER, KEY_ENTER, KEY_HOME"),
      token: z.string().optional().describe("Token salvo de conexões anteriores (porta 8002)"),
    },
  },
  async ({ ip, tecla, token }) => {
    const name = Buffer.from("MCP TV Cast").toString("base64");
    const url = `wss://${ip}:8002/api/v2/channels/samsung.remote.control?name=${name}${token ? `&token=${token}` : ""}`;
    return new Promise((resolve) => {
      const ws = new WebSocket(url, { rejectUnauthorized: false }); // TV usa certificado autoassinado
      const timer = setTimeout(() => { ws.terminate(); resolve(fail("Timeout — aceite o pedido na TV e tente de novo.")); }, 30_000);
      ws.on("message", (raw) => {
        const msg = JSON.parse(raw.toString());
        if (msg.event === "ms.channel.connect") {
          ws.send(JSON.stringify({
            method: "ms.remote.control",
            params: { Cmd: "Click", DataOfCmd: tecla, Option: "false", TypeOfRemote: "SendRemoteKey" },
          }));
          setTimeout(() => {
            clearTimeout(timer);
            ws.close();
            const novo = msg.data?.token ? ` Token: ${msg.data.token} (guarde para não pedir autorização de novo)` : "";
            resolve(text(`Tecla ${tecla} enviada para ${ip}.${novo}`));
          }, 500);
        } else if (msg.event === "ms.channel.unauthorized") {
          clearTimeout(timer); ws.close(); resolve(fail("A TV recusou a conexão."));
        }
      });
      ws.on("error", (e) => { clearTimeout(timer); resolve(fail(e)); });
    });
  },
);

// ---------------------------------------------------------------- Android TV / Google TV (ADB)
// Muito mais rápido e estável que Win + K: conexão direta por rede (ADB) + scrcpy para espelhar.

const ADB = process.env.ADB_PATH || "adb";
const SCRCPY = process.env.SCRCPY_PATH || "scrcpy";

async function adb(args: string[], serial?: string, timeout = 20_000): Promise<string> {
  const full = serial ? ["-s", serial, ...args] : args;
  try {
    const { stdout, stderr } = await run(ADB, full, { windowsHide: true, timeout, maxBuffer: 10 * 1024 * 1024 });
    return (stdout || stderr).trim();
  } catch (e: any) {
    if (e?.code === "ENOENT")
      throw new Error("adb não encontrado. Rode a ferramenta 'instalar_ferramentas' ou defina ADB_PATH.");
    throw e;
  }
}
const sh = (cmd: string, serial?: string, timeout?: number) => adb(["shell", cmd], serial, timeout);

const alvo = z.string().optional().describe("IP:porta da TV (ex.: 192.168.0.50:5555). Omita se só houver um dispositivo.");

server.registerTool(
  "instalar_ferramentas",
  {
    description: "Instala adb (Platform Tools) e scrcpy no Windows via winget, se ainda não estiverem instalados.",
    inputSchema: {},
  },
  async () => {
    try {
      const out = await ps(
        "foreach ($p in 'Google.PlatformTools','Genymobile.scrcpy') { winget install --id $p -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String }",
      );
      return text(out + "\nReabra o terminal/Claude para o PATH atualizar.");
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_conectar",
  {
    description:
      "Conecta à TV Android/Google TV por ADB via rede (rápido, sem Win + K). Na TV: Configurações > Sobre > clique 7x em 'Build' > " +
      "Opções do desenvolvedor > ative 'Depuração USB/ADB' e 'Depuração de rede'. Aceite o pedido de autorização na TV na primeira vez.",
    inputSchema: { ip: z.string().describe("IP da TV na rede"), porta: z.number().default(5555) },
  },
  async ({ ip, porta }) => {
    try {
      return text(await adb(["connect", `${ip}:${porta}`], undefined, 15_000));
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_dispositivos",
  { description: "Lista dispositivos ADB conectados (e se estão autorizados).", inputSchema: {} },
  async () => {
    try {
      return text(await adb(["devices", "-l"]));
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_info",
  {
    description: "Diagnóstico da TV: modelo, Android, RAM livre, armazenamento, temperatura, sinal Wi-Fi e os apps que mais consomem memória.",
    inputSchema: { serial: alvo },
  },
  async ({ serial }) => {
    try {
      const [model, ver, mem, disk, wifi, top] = await Promise.all([
        sh("getprop ro.product.model; getprop ro.build.version.release", serial),
        sh("getprop ro.build.version.sdk", serial),
        sh("grep -E 'MemTotal|MemAvailable' /proc/meminfo", serial),
        sh("df -h /data | tail -n 1", serial),
        sh("dumpsys wifi | grep -m3 -E 'RSSI|rssi|frequency'", serial).catch(() => "n/d"),
        sh("dumpsys meminfo | sed -n '/Total PSS by process/,/^$/p' | head -n 12", serial).catch(() => "n/d"),
      ]);
      return text(
        `Modelo/Android:\n${model} (SDK ${ver})\n\nMemória:\n${mem}\n\nArmazenamento (/data):\n${disk}\n\nWi-Fi:\n${wifi}\n\nTop memória:\n${top}`,
      );
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_listar_apps",
  {
    description: "Lista apps instalados na TV (de terceiros por padrão; 'sistema' inclui bloatware que pode ser desativado).",
    inputSchema: { tipo: z.enum(["terceiros", "sistema", "desativados"]).default("terceiros"), serial: alvo },
  },
  async ({ tipo, serial }) => {
    try {
      const flag = { terceiros: "-3", sistema: "-s", desativados: "-d" }[tipo];
      return text(await sh(`pm list packages ${flag} | sed 's/package://' | sort`, serial));
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_otimizar",
  {
    description:
      "Otimiza a TV para ficar mais ágil: encerra processos em segundo plano, limpa caches, reduz/desliga animações e limita processos em background. " +
      "Opcionalmente desativa apps (reversível com tv_reativar_app; não desinstala).",
    inputSchema: {
      animacoes: z.enum(["manter", "reduzir", "desligar"]).default("reduzir").describe("Escala de animação: 0.5x ou 0x"),
      limitar_background: z.boolean().default(true).describe("Limita a 2 processos em segundo plano"),
      desativar_apps: z.array(z.string()).default([]).describe("Pacotes a desativar (ex.: bloatware listado em tv_listar_apps sistema)"),
      serial: alvo,
    },
  },
  async ({ animacoes, limitar_background, desativar_apps, serial }) => {
    const log: string[] = [];
    const step = async (nome: string, cmd: string) => {
      try { await sh(cmd, serial, 60_000); log.push(`✔ ${nome}`); }
      catch (e) { log.push(`✘ ${nome}: ${e instanceof Error ? e.message : e}`); }
    };
    try {
      const antes = await sh("grep MemAvailable /proc/meminfo", serial);
      await step("Encerrar processos em segundo plano", "am kill-all");
      await step("Limpar caches de todos os apps", "pm trim-caches 999G");
      if (animacoes !== "manter") {
        const v = animacoes === "desligar" ? "0" : "0.5";
        await step(`Animações ${v}x`, `settings put global window_animation_scale ${v}; settings put global transition_animation_scale ${v}; settings put global animator_duration_scale ${v}`);
      }
      if (limitar_background) await step("Limitar processos em background (2)", "settings put global background_process_limit 2 2>/dev/null; am memory-factor 2>/dev/null; true");
      for (const pkg of desativar_apps) {
        if (!/^[A-Za-z0-9_.]+$/.test(pkg)) { log.push(`✘ pacote inválido: ${pkg}`); continue; }
        await step(`Desativar ${pkg}`, `pm disable-user --user 0 ${pkg}`);
      }
      const depois = await sh("grep MemAvailable /proc/meminfo", serial);
      return text(`${log.join("\n")}\n\nMemória disponível antes: ${antes}\nDepois: ${depois}\n\nDica: reinicie a TV (tv_reiniciar) para aplicar tudo.`);
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_reativar_app",
  {
    description: "Reativa um app desativado por tv_otimizar.",
    inputSchema: { pacote: z.string().regex(/^[A-Za-z0-9_.]+$/), serial: alvo },
  },
  async ({ pacote, serial }) => {
    try {
      return text(await sh(`pm enable ${pacote}`, serial));
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_tecla",
  {
    description: "Envia uma tecla do controle remoto (ex.: HOME, BACK, POWER, VOLUME_UP, VOLUME_DOWN, MUTE, DPAD_CENTER, TV_INPUT).",
    inputSchema: { tecla: z.string().regex(/^[A-Z0-9_]+$/).describe("Nome sem o prefixo KEYCODE_"), serial: alvo },
  },
  async ({ tecla, serial }) => {
    try {
      await sh(`input keyevent KEYCODE_${tecla}`, serial);
      return text(`Tecla ${tecla} enviada.`);
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_abrir_app",
  {
    description: "Abre um app na TV pelo nome do pacote (ex.: com.google.android.youtube.tv, com.netflix.ninja).",
    inputSchema: { pacote: z.string().regex(/^[A-Za-z0-9_.]+$/), serial: alvo },
  },
  async ({ pacote, serial }) => {
    try {
      return text(await sh(`monkey -p ${pacote} -c android.intent.category.LAUNCHER 1`, serial));
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_reiniciar",
  { description: "Reinicia a TV (libera memória e aplica as otimizações).", inputSchema: { serial: alvo } },
  async ({ serial }) => {
    try {
      await adb(["reboot"], serial);
      return text("Reiniciando a TV. Aguarde ~1 min e use tv_conectar de novo.");
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_miracast_receber",
  {
    description:
      "Abre o receptor Miracast na TV (ADB) e o painel Win + K no PC, deixando tudo pronto para espelhar a tela inteira do computador sem fio.",
    inputSchema: { serial: alvo },
  },
  async ({ serial }) => {
    try {
      await sh("input keyevent KEYCODE_WAKEUP; am start -n com.droidlogic.miracast/.WiFiDirectMainActivity", serial);
      await ps("Start-Process 'ms-settings-connectabledevices:devicediscovery'");
      return text("Receptor aberto na TV e painel Win + K aberto no PC. Escolha a TV (nome 'SmartTV_xxxx') na lista.");
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  "tv_espelhar",
  {
    description:
      "Abre a tela da TV numa janela no PC (scrcpy), com controle por teclado/mouse. Muito mais rápido que Win + K. " +
      "Parâmetros baixos de bitrate/resolução deixam fluido em Wi-Fi fraco.",
    inputSchema: {
      max_resolucao: z.number().default(1280).describe("Maior lado em px (720–1920)"),
      bitrate_mbps: z.number().default(6),
      fps: z.number().default(30),
      serial: alvo,
    },
  },
  async ({ max_resolucao, bitrate_mbps, fps, serial }) => {
    try {
      const args = ["--max-size", String(max_resolucao), "--video-bit-rate", `${bitrate_mbps}M`, "--max-fps", String(fps), "--no-audio"];
      if (serial) args.unshift("--serial", serial);
      const child = spawn(SCRCPY, args, { detached: true, stdio: "ignore", windowsHide: false });
      child.on("error", () => {});
      child.unref();
      return text("scrcpy iniciado. Se nada abrir, rode 'instalar_ferramentas' e confirme a autorização ADB na TV.");
    } catch (e) {
      return fail(e);
    }
  },
);

await server.connect(new StdioServerTransport());
