// 清點用的解析器。三種模式，都只讀不寫：
//   node mcp-config.cjs file    讀 MCP_CONFIG 指的 JSON，吐出 TSV 列
//   node mcp-config.cjs cli     讀 stdin 上 `claude mcp list` 的輸出，吐出 TSV 列
//   node mcp-config.cjs table   讀 stdin 上的 TSV 列，排版成表格加註記
//   node mcp-config.cjs mask    讀 stdin 的自由文字，把 NAME=值 的值換成 ***
//
// 副檔名是 .cjs 的理由跟 mcp-rpc.cjs 一樣，見那支的檔頭。
//
// 遮蔽只寫在這一支裡。file 與 cli 兩路都不把值搬到輸出上，而 list-tools.sh 要把
// 讀者打的那串指令回印一次（裡面可能有 -e FOO=值），它走 mask 模式。
// 分兩份寫的話，補了一邊漏了另一邊的時候畫面上看不出來，而漏的那一邊就是憑證外流。
//
// TSV 的欄位：來源 \t 傳輸 \t 憑證 \t 名稱 \t 範圍 \t 旗標
// 旗標是給註記用的，逗號分隔：cred（帶憑證）remote（範圍看不出來）
// wide（範圍是整台或整個家目錄）credunknown（這個來源看不到憑證）

const fs = require("fs");
const os = require("os");
const path = require("path");

const die = (msg, code) => { fs.writeSync(2, msg); process.exit(code); };
const mode = process.argv[2];

// ── 憑證 ──────────────────────────────────────────────────
// 值一律不印，不分變數叫什麼名字：這支腳本從來沒有把值搬到輸出上的路徑。
// 下面這份名字樣式只決定兩件事：那一格印不印 =***，以及要不要在收尾點名這一台。
//
// 為什麼不做成「符合樣式的才遮、其餘照印」：那種寫法的失手成本是印出一個真的憑證，
// 而樣式清單永遠會漏（實測看到過一個叫 mcp-cluster-id 的 header，
// 六個常見字樣一個都不沾，值是 36 個字元）。改成「值一律不印」之後，
// 清單漏掉一個名字的後果只剩少一個提醒，而不是外流。
// 自由文字的遮蔽不篩名字：任何 NAME=VALUE 的值一律換成 ***。
// 只遮「名字像憑證」的話，一個叫 PT 或 gh_pat 的變數就會整串留在畫面上。
function maskInline(text) {
  return text
    .replace(/([A-Za-z_][A-Za-z0-9_.-]*=)(\S+)/g, "$1***")
    .replace(/((?:Authorization|Proxy-Authorization)\s*:\s*)(\S.*)$/gim, "$1***")
    .replace(/\b(Bearer|Basic|token)\s+\S+/gi, "$1 ***");
}

const CRED = /(TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|API[-_]?KEY|_KEY$|^KEY$|KEYS?$|AUTH|BEARER|SESSION|COOKIE|PRIVATE|SIGNATURE)/i;
const looksLikeCred = (name) => CRED.test(name);

// ── 路徑 ──────────────────────────────────────────────────
// 讀者的目錄樹不印出來，只留最後一段。但「整台」跟「整個家目錄」這兩種要看得出來，
// 收斂成 basename 會把最重要的那個訊息弄丟：範圍是 / 的時候 basename 是空的。
// 這一欄刻意全部用半形字元，這樣表格的欄寬不必去猜終端機怎麼算全形字。
function collapsePath(p) {
  const home = os.homedir();
  let s = String(p).replace(/\/+$/, "");
  if (s === "" || s === "/") return "/ (whole machine)";
  if (s === "~" || s === home) return "~ (whole home)";
  const base = path.basename(s);
  if (s === home + "/" + base) return "~/" + base;
  if (s.startsWith(home + "/")) return "~/.../" + base;
  if (s.startsWith("~/")) return "~/.../" + base;
  return ".../" + base;
}

const looksLikePath = (a) => /^[/~]/.test(String(a));

// stdio 的檔案系統範圍只能從啟動參數裡的路徑推。推不到不等於它碰不到東西：
// 一台不吃路徑參數的 server 可能自己寫死了範圍，也可能整台都能碰。
// 所以推不到的時候印 unknown，不印「無」。
function scopeFromArgs(args) {
  const hits = [];
  for (const raw of args) {
    const a = String(raw);
    const eq = a.indexOf("=");
    const cand = a.startsWith("--") && eq > 0 ? a.slice(eq + 1) : a;
    if (looksLikePath(cand)) hits.push(collapsePath(cand));
  }
  return hits.length ? hits.join(" ") : "unknown";
}

const isWide = (scope) => /whole machine|whole home/.test(scope);

// 憑證欄：宣告過的變數名全部列出來，看起來像憑證的後面補 =***。
// 值沒有一個會被印出來，=*** 的意思是「這裡有個值，我判定它是憑證，不給你看」，
// 光禿禿的名字是「宣告了這個變數，值一樣不給你看」。
// 沒列出來就等於沒宣告，所以樣式沒中的變數不會消失，只是少一個 =***。
function row(o) {
  const flags = [];
  const creds = o.vars.filter(looksLikeCred);
  if (creds.length) flags.push("cred");
  if (o.credUnknown) flags.push("credunknown");
  if (o.scope === "remote") flags.push("remote");
  if (isWide(o.scope)) flags.push("wide");
  const credCell = o.credUnknown ? "?"
    : (o.vars.length ? o.vars.map((n) => (looksLikeCred(n) ? n + "=***" : n)).join(",") : "no");
  return [o.source, o.transport, credCell, o.name, o.scope, flags.join(",")].join("\t");
}

// ── file 模式 ─────────────────────────────────────────────
function fromFile() {
  const p = process.env.MCP_CONFIG || path.join(os.homedir(), ".claude.json");
  let j;
  try {
    j = JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    die("讀不到或解不開 " + p + "：" + e.message + "\n", 2);
  }
  const out = [];
  const emit = (source, name, s) => {
    const env = s.env && typeof s.env === "object" ? Object.keys(s.env) : [];
    const headers = s.headers && typeof s.headers === "object" ? Object.keys(s.headers) : [];
    const args = Array.isArray(s.args) ? s.args : [];
    // args 裡的 NAME=VALUE 也算宣告變數（docker run -e FOO=bar 就是這種）。
    // 只看 env 欄位會漏掉這一整類，而它們是真的會傳進 server 的。
    const inArgs = args.map((a) => String(a).match(/^([A-Za-z_][A-Za-z0-9_]*)=/))
      .filter(Boolean).map((m) => m[1]);
    const names = env.concat(headers).concat(inArgs);

    // type 欄位可以不寫。有 command 就是 stdio，這是實測到的形狀：
    // 同一份設定裡有一台只有 command 跟 args、沒有 type。
    // 用 type === "stdio" 判斷的話那一台會被算成 unknown，然後它的範圍不會被推。
    let transport = String(s.type || "").toLowerCase();
    if (!transport) transport = s.command ? "stdio" : (s.url ? "http" : "unknown");

    const scope = s.command ? scopeFromArgs([].concat(s.command, args))
      : (s.url ? "remote" : "unknown");

    out.push(row({
      source: source,
      transport: transport,
      vars: names,
      credUnknown: false,
      name: name,
      scope: scope,
    }));
  };

  const global = j.mcpServers && typeof j.mcpServers === "object" ? j.mcpServers : {};
  for (const [name, s] of Object.entries(global)) emit("global", name, s);

  // 這一段是這支腳本存在的理由。全域那一份可以是空的，而每個專案各自帶一份設定，
  // 那些設定只出現在 projects.<路徑>.mcpServers 底下。
  // 只讀全域的話會回報「一台都沒有」，而實際上你機器上跑著好幾台。
  const projects = j.projects && typeof j.projects === "object" ? j.projects : {};
  for (const [proj, v] of Object.entries(projects)) {
    const ms = v && typeof v === "object" && v.mcpServers && typeof v.mcpServers === "object" ? v.mcpServers : null;
    if (!ms) continue;
    const tag = "proj:" + path.basename(String(proj).replace(/\/+$/, ""));
    for (const [name, s] of Object.entries(ms)) emit(tag, name, s);
  }
  process.stdout.write(out.map((r) => r + "\n").join(""));
}

// ── cli 模式 ──────────────────────────────────────────────
// `claude mcp list` 印的是一行一台：`名稱: 那一串 - 狀態`。
// 那一串對 stdio 是完整的啟動命令列（包含 -e FOO=值，值是原樣印的），
// 對 http／sse 是 URL 加一個 (HTTP)／(SSE) 標記。
function fromCli() {
  const text = fs.readFileSync(0, "utf8");
  const out = [];
  for (const line0 of text.split("\n")) {
    const line = line0.replace(/\s+$/, "");
    if (!line) continue;
    // 這幾行不是 server：健康檢查的抬頭、什麼都沒設定的提示、離開碼。
    if (/^(Checking MCP server health|No MCP servers configured|EXIT=)/.test(line)) continue;
    const m = line.match(/^(.+?): (.*?)(?: - [^ ].*)?$/);
    if (!m) continue;
    const name = m[1];
    const rest = m[2];
    let transport = "stdio";
    if (/\(SSE\)\s*$/.test(rest)) transport = "sse";
    else if (/\(HTTP\)\s*$/.test(rest)) transport = "http";
    else if (/^https?:\/\//.test(rest)) transport = "http";

    if (transport === "stdio") {
      const parts = rest.split(/\s+/);
      const names = parts.map((a) => a.match(/^([A-Za-z_][A-Za-z0-9_]*)=/))
        .filter(Boolean).map((x) => x[1]);
      out.push(row({
        source: "cli",
        transport: transport,
        vars: names,
        credUnknown: false,
        name: name,
        scope: scopeFromArgs(parts),
      }));
    } else {
      // CLI 這一路對遠端那幾台只印 URL。設定檔裡 headers 底下的憑證它不印，
      // 所以這裡的憑證欄是「?」不是「無」：沒看到不等於沒有。
      out.push(row({
        source: "cli",
        transport: transport,
        vars: [],
        credUnknown: true,
        name: name,
        scope: "remote",
      }));
    }
  }
  process.stdout.write(out.map((r) => r + "\n").join(""));
}

// ── table 模式 ────────────────────────────────────────────
// 全形字在終端機佔兩個顯示欄位，而字串長度是按字元數算的。
// 直接用長度補空白，帶中文的那幾格會比別人短，整張表就歪了。
const WIDE = /[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE6F\uFF00-\uFF60\uFFE0-\uFFE6]/;
const dispWidth = (s) => Array.from(String(s)).reduce((a, c) => a + (WIDE.test(c) ? 2 : 1), 0);
const pad = (s, w) => String(s) + " ".repeat(Math.max(0, w - dispWidth(s)));

function table() {
  const text = fs.readFileSync(0, "utf8");
  const rows = text.split("\n").filter((s) => s.length).map((s) => s.split("\t"));
  const head = ["來源", "傳輸", "憑證", "名稱", "範圍"];
  if (!rows.length) {
    process.stdout.write("一台都沒有清點到。\n");
    process.stdout.write("那不一定代表你沒裝：設定可能在別的地方，或者這一路的來源沒打開。\n");
    return;
  }
  const cols = head.length;
  const w = head.map((h, i) => Math.max(dispWidth(h), ...rows.map((r) => dispWidth(r[i] || ""))));
  const render = (cells) => cells.slice(0, cols).map((c, i) =>
    (i === cols - 1 ? String(c) : pad(c, w[i]))).join("  ");
  process.stdout.write("憑證欄：看起來像憑證的變數印成「名字=***」，其餘只印名字，值一律不印。\n");
  process.stdout.write("        no 是沒宣告變數，? 是這個來源看不到（不等於沒有）。\n");
  process.stdout.write("範圍欄：remote 是遠端那一台，unknown 是啟動參數裡推不出路徑。兩種都不是「碰不到」。\n\n");
  process.stdout.write(render(head) + "\n");
  for (const r of rows) process.stdout.write(render(r) + "\n");

  // 註記。表格印得出東西不代表你看懂了，所以把三件事單獨講一次。
  const has = (r, f) => (r[5] || "").split(",").indexOf(f) >= 0;
  const names = (f) => rows.filter((r) => has(r, f)).map((r) => r[3]);
  const cred = names("cred");
  const unknownCred = names("credunknown");
  const remote = names("remote");
  const wide = names("wide");
  const noscope = rows.filter((r) => r[4] === "unknown").map((r) => r[3]);

  if (cred.length) {
    process.stdout.write("\n── 這幾台帶著憑證 ──\n" + cred.join(" ") + "\n");
    process.stdout.write("憑證欄印的是變數名，值一個字都沒印。要看值請自己開設定檔。\n");
  }
  if (wide.length) {
    process.stdout.write("\n── 這幾台的宣告範圍是整台或整個家目錄 ──\n" + wide.join(" ") + "\n");
  }
  if (remote.length || noscope.length) {
    process.stdout.write("\n── 這幾台碰得到什麼，設定檔看不出來 ──\n");
    if (remote.length) process.stdout.write("遠端（http／sse）：" + remote.join(" ") + "\n");
    if (noscope.length) process.stdout.write("啟動參數裡沒有路徑：" + noscope.join(" ") + "\n");
    process.stdout.write("範圍那一欄印 remote 或 unknown 的意思是「我推不出來」，不是「它碰不到東西」。\n");
    process.stdout.write("要知道它碰得到什麼，只有問它自己：bash list-tools.sh <啟動指令>。\n");
  }
  if (unknownCred.length) {
    process.stdout.write("\n── 這幾台的憑證欄是「?」──\n" + unknownCred.join(" ") + "\n");
    process.stdout.write("CLI 那一路只印 URL，設定檔 headers 底下的憑證它不印。沒看到不等於沒有。\n");
  }
}

if (mode === "file") fromFile();
else if (mode === "cli") fromCli();
else if (mode === "table") table();
else if (mode === "mask") process.stdout.write(maskInline(fs.readFileSync(0, "utf8")));
else die("用法：node mcp-config.cjs file|cli|table|mask\n", 2);
