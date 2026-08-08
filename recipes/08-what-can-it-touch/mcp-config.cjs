// 清點用的解析器。五種模式，都只讀不寫：
//   node mcp-config.cjs file    讀 MCP_CONFIG 指的 JSON，吐出 TSV 列
//   node mcp-config.cjs roots   讀 MCP_ROOTS 每個目錄底下的 .mcp.json，吐出 TSV 列
//   node mcp-config.cjs cli     讀 stdin 上 `claude mcp list` 的輸出，吐出 TSV 列
//   node mcp-config.cjs table   讀 stdin 上的 TSV 列，排版成表格加註記
//   node mcp-config.cjs mask    讀 stdin 的自由文字，把 NAME=值 的值換成 ***
//
// 副檔名是 .cjs 的理由跟 mcp-rpc.cjs 一樣，見那支的檔頭。
//
// 遮蔽只寫在這一支裡。file、roots 與 cli 三路都不把值搬到輸出上，而 list-tools.sh 要把
// 讀者打的那串指令回印一次（裡面可能有 -e FOO=值），它走 mask 模式。
// 分兩份寫的話，補了一邊漏了另一邊的時候畫面上看不出來，而漏的那一邊就是憑證外流。
//
// TSV 的欄位：來源 \t 傳輸 \t 憑證 \t 名稱 \t 範圍 \t 旗標
// 旗標是給註記用的，逗號分隔：cred（帶憑證）remote（範圍看不出來）
// wide（範圍是整台或整個家目錄）credunknown（這個來源看不到憑證）
// credliteral（憑證的值明文寫在檔案裡）credvar（憑證用 ${VAR}，值不在檔案裡）

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

// ── 值是明文還是一個 ${VAR} 參照 ──────────────────────────
// 官方在 .mcp.json（還有 ~/.claude.json）支援 ${VAR} 與 ${VAR:-預設} 展開，
// 而這支從來不展開它：展開等於把環境變數的值搬到輸出上，那正是這裡不做的事。
//
// 這兩種要分得開，因為它們的後果不一樣。.mcp.json 預設要進版本庫，
// 明文那一種會跟著 git 走出去，${VAR} 那一種留在讀者自己的環境裡。
// 混為一談的話，一份安全的設定跟一份會外流的設定在表上長得一樣。
//
// ${VAR:-預設} 算在明文那一邊：那個預設值是真的寫在檔案裡的，所以它也不印。
// 判不出來的時候一律往嚴的算（明文），因為反過來的失手成本是漏報一個真的外流。
const VARREF = /\$\{[^}]*\}/g;
function classifyValue(value) {
  const s = String(value);
  const refs = s.match(VARREF) || [];
  if (!refs.length) return { kind: "literal", shown: "***" };
  if (refs.some((r) => r.indexOf(":-") >= 0)) return { kind: "literal", shown: "***" };
  // ${...} 以外還剩字母數字的話，值有一部分是寫死在檔案裡的。
  // Authorization 那一格的 Bearer／Basic／token 是傳輸前綴，不是值。
  const rest = s.replace(VARREF, "").replace(/\b(Bearer|Basic|token)\b/gi, "");
  if (/[A-Za-z0-9]/.test(rest)) return { kind: "literal", shown: "***" };
  return { kind: "var", shown: refs.join("") };
}

const declare = (name, value) => Object.assign({ name: name }, classifyValue(value));

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

// 啟動參數裡的路徑，跟「這台 server 碰得到哪裡」是兩件事。
//
// 第一版把任何看起來像路徑的參數都當成範圍，那是錯的，而且錯得剛好是這份 recipe
// 最反對的那種：`node /home/me/mcp/server.js --config /home/me/mcp/c.json` 會印出
// 一個看起來很精準的「範圍」，但那兩個只是程式檔跟設定檔，跟它讀得到哪裡無關。
// 讀者會拿到一張看似精確、實際把執行檔路徑當權限邊界的表。
//
// 現在的規則：**只有已知參數語意的 server 才填範圍，其他一律 unknown。**
// 路徑資訊沒有丟掉，改放在另一欄，那一欄叫「啟動參數裡的路徑」不叫範圍。
//
// 這張表要長，唯一的加法是去讀那台 server 的文件、確認它的位置參數真的是
// allowed directory，然後把它加進來。加之前先問：這台 server 有沒有可能在
// 這些路徑以外的地方讀寫？答不出來就不要加。
const FS_PKG = /@modelcontextprotocol\/server-filesystem(@|$)/;

const KNOWN_SCOPE_ARGS = [
  {
    // 官方 filesystem server：套件名後面的位置參數就是 allowed directories，
    // README 明講 `Specify Allowed directories when starting the server`。
    match: FS_PKG,
    // 每台自己帶抽取器，不共用一個「看起來像路徑就算」的通則。
    // command 一律不參與：`/opt/homebrew/bin/npx` 是執行檔位置，
    // 把它算進範圍就會印出一個看起來很精準的假邊界。
    extract: function (command, args) {
      const i = args.findIndex((a) => FS_PKG.test(String(a)));
      if (i < 0) return [];
      return args.slice(i + 1).map(String).filter(looksLikePath).map(collapsePath);
    },
  },
];

function pathsInArgs(args) {
  const hits = [];
  for (const raw of args) {
    const a = String(raw);
    const eq = a.indexOf("=");
    const cand = a.startsWith("--") && eq > 0 ? a.slice(eq + 1) : a;
    if (looksLikePath(cand)) hits.push(collapsePath(cand));
  }
  return hits;
}

// 回傳 { scope, argPaths }。
// scope 只在認得那台 server 的時候才填，而且只由那台自己的抽取器決定。
// argPaths 是「命令列上出現過的路徑」，含 command，那一欄不叫範圍。
function scopeFromArgs(command, args) {
  const all = [].concat(command == null ? [] : command, args).map(String);
  const argPaths = pathsInArgs(all);
  const known = KNOWN_SCOPE_ARGS.find((k) => all.some((a) => k.match.test(a)));
  if (!known) return { scope: "unknown", argPaths: argPaths };
  const dirs = known.extract(command == null ? "" : String(command), args.map(String));
  return { scope: dirs.length ? dirs.join(" ") : "unknown", argPaths: argPaths };
}

const isWide = (scope) => /whole machine|whole home/.test(scope);

// 憑證欄：宣告過的變數名全部列出來，看起來像憑證的後面補值的形狀。
// 值沒有一個會被印出來。=*** 的意思是「這裡有個值，我判定它是憑證，不給你看」，
// =${VAR} 的意思是「這裡是一個變數參照，值不在這個檔案裡」，
// 光禿禿的名字是「宣告了這個變數，值一樣不給你看」。
// 沒列出來就等於沒宣告，所以樣式沒中的變數不會消失，只是少一個提醒。
const credText = (v) => (looksLikeCred(v.name) ? v.name + "=" + v.shown : v.name);

function row(o) {
  const flags = [];
  const creds = o.vars.filter((v) => looksLikeCred(v.name));
  if (creds.length) flags.push("cred");
  if (o.credUnknown) flags.push("credunknown");
  if (o.scope === "remote") flags.push("remote");
  if (isWide(o.scope)) flags.push("wide");
  if (creds.some((v) => v.kind === "literal")) flags.push("credliteral");
  if (creds.some((v) => v.kind === "var")) flags.push("credvar");
  const credCell = o.credUnknown ? "?"
    : (o.vars.length ? o.vars.map(credText).join(",") : "no");
  // 範圍與「啟動參數裡的路徑」分兩欄，因為它們是兩件事：
  // 前者是這台 server 宣告它會碰哪裡，後者只是命令列上出現過的路徑。
  const argPathCell = (o.argPaths && o.argPaths.length) ? o.argPaths.join(" ") : "-";
  return [o.source, o.transport, credCell, o.name, o.scope, argPathCell, flags.join(",")].join("\t");
}

// ── 一台 server 的設定長什麼樣 ────────────────────────────
// file 與 roots 兩路吃的是同一種物件（~/.claude.json 與 .mcp.json 的 mcpServers
// 底下是同一個格式），所以解析只寫一份。分兩份寫的話，補了一邊漏了另一邊，
// 而漏的那一邊會靜靜地少報幾個變數。
function serverRow(source, name, s) {
  const vars = [];
  const take = (obj) => {
    if (!obj || typeof obj !== "object") return;
    for (const [k, v] of Object.entries(obj)) vars.push(declare(k, v));
  };
  take(s.env);
  take(s.headers);

  const args = Array.isArray(s.args) ? s.args : [];
  // args 裡的 NAME=VALUE 也算宣告變數（docker run -e FOO=bar 就是這種）。
  // 只看 env 欄位會漏掉這一整類，而它們是真的會傳進 server 的。
  for (const a of args) {
    const m = String(a).match(/^([A-Za-z_][A-Za-z0-9_]*)=([\s\S]*)$/);
    if (m) vars.push(declare(m[1], m[2]));
  }

  // type 欄位可以不寫。有 command 就是 stdio，這是實測到的形狀：
  // 同一份設定裡有一台只有 command 跟 args、沒有 type。
  // 用 type === "stdio" 判斷的話那一台會被算成 unknown，然後它的範圍不會被推。
  let transport = String(s.type || "").toLowerCase();
  if (!transport) transport = s.command ? "stdio" : (s.url ? "http" : "unknown");

  const sc = s.command ? scopeFromArgs(s.command, args)
    : { scope: (s.url ? "remote" : "unknown"), argPaths: [] };

  return row({
    source: source,
    transport: transport,
    vars: vars,
    credUnknown: false,
    name: name,
    scope: sc.scope,
    argPaths: sc.argPaths,
  });
}

const serversOf = (j) => (j && typeof j.mcpServers === "object" && j.mcpServers ? j.mcpServers : {});

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

  const global = serversOf(j);
  for (const [name, s] of Object.entries(global)) out.push(serverRow("global", name, s));

  // 這一段是這支腳本存在的理由。全域那一份可以是空的，而每個專案各自帶一份設定，
  // 那些設定只出現在 projects.<路徑>.mcpServers 底下。
  // 只讀全域的話會回報「一台都沒有」，而實際上你機器上跑著好幾台。
  const projects = j.projects && typeof j.projects === "object" ? j.projects : {};
  for (const [proj, v] of Object.entries(projects)) {
    const ms = v && typeof v === "object" && v.mcpServers && typeof v.mcpServers === "object" ? v.mcpServers : null;
    if (!ms) continue;
    const tag = "proj:" + path.basename(String(proj).replace(/\/+$/, ""));
    for (const [name, s] of Object.entries(ms)) out.push(serverRow(tag, name, s));
  }
  process.stdout.write(out.map((r) => r + "\n").join(""));
}

// ── roots 模式 ────────────────────────────────────────────
// 第三個來源：專案根目錄的 .mcp.json。官方講的三個安裝範圍（local／project／user）
// 裡的 project 那一路，設計上就是要進版本庫跟團隊共享的那一份。
// ~/.claude.json 讀到的是 local 與 user，這一路完全在那份檔案之外。
//
// MCP_ROOTS 是冒號分隔的目錄清單，一個目錄看一份 .mcp.json。
// 第一行是 ROOTS<TAB>看了幾個<TAB>找到幾份<TAB>解不開幾份<TAB>解不開的專案名，
// 給 inventory.sh 印那段訊息用，不進表格。
// 那一行存在的理由是「看了沒找到」跟「根本沒看」在畫面上必須長得不一樣。
function fromRoots() {
  const spec = process.env.MCP_ROOTS || process.cwd();
  const dirs = spec.split(":").map((s) => s.trim()).filter((s) => s.length);
  const out = [];
  const broken = [];
  let found = 0;

  for (const d of dirs) {
    // 專案名只留最後一段。整條路徑印出來的話，一張清點表就把目錄樹交出去了。
    const proj = path.basename(path.resolve(d)) || "/";
    let raw;
    try {
      raw = fs.readFileSync(path.join(d, ".mcp.json"), "utf8");
    } catch (e) {
      // 沒有那個檔是一個答案（這個專案沒有專案級設定），讀不到是另一件事。
      if (e.code !== "ENOENT") broken.push(proj);
      continue;
    }
    let j;
    try {
      j = JSON.parse(raw);
    } catch (e) {
      broken.push(proj);
      continue;
    }
    found++;
    for (const [name, s] of Object.entries(serversOf(j))) {
      out.push(serverRow("mcp.json:" + proj, name, s));
    }
  }

  process.stdout.write(["ROOTS", dirs.length, found, broken.length, broken.join(" ")].join("\t") + "\n");
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
    // 這幾行不是 server：健康檢查的抬頭、什麼都沒設定的提示、結束碼。
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
      const vars = [];
      for (const a of parts) {
        const kv = a.match(/^([A-Za-z_][A-Za-z0-9_]*)=([\s\S]*)$/);
        if (kv) vars.push(declare(kv[1], kv[2]));
      }
      out.push(row({
        source: "cli",
        transport: transport,
        vars: vars,
        credUnknown: false,
        name: name,
        scope: scopeFromArgs(parts[0], parts.slice(1)).scope,
        argPaths: scopeFromArgs(parts[0], parts.slice(1)).argPaths,
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
  const head = ["來源", "傳輸", "憑證", "名稱", "範圍", "啟動參數裡的路徑"];
  if (!rows.length) {
    process.stdout.write("一台都沒有清點到。\n");
    process.stdout.write("那不一定代表你沒裝：設定可能在別的地方，或者這一路的來源沒打開。\n");
    return;
  }
  const cols = head.length;
  const w = head.map((h, i) => Math.max(dispWidth(h), ...rows.map((r) => dispWidth(r[i] || ""))));
  const render = (cells) => cells.slice(0, cols).map((c, i) =>
    (i === cols - 1 ? String(c) : pad(c, w[i]))).join("  ");
  process.stdout.write("來源欄：global 與 proj: 來自 ~/.claude.json，mcp.json: 來自專案根目錄的 .mcp.json。\n");
  process.stdout.write("憑證欄：看起來像憑證的變數印成「名字=***」，其餘只印名字，值一律不印。\n");
  process.stdout.write("        名字=${VAR} 是值不在檔案裡、指向一個環境變數，原樣印出來不展開。\n");
  process.stdout.write("        no 是沒宣告變數，? 是這個來源看不到（不等於沒有）。\n");
  process.stdout.write("範圍欄：只有這支認得參數語意的 server 才填（目前只有官方 filesystem server）。\n");
  process.stdout.write("        remote 是遠端那一台，unknown 是「我不知道」，兩種都不是「碰不到」。\n");
  process.stdout.write("最後一欄：命令列上出現過的路徑。那不是權限範圍，多數只是程式檔或設定檔的位置。\n\n");
  process.stdout.write(render(head) + "\n");
  for (const r of rows) process.stdout.write(render(r) + "\n");

  // 註記。表格印得出東西不代表你看懂了，所以把幾件事單獨講一次。
  // 點名一律印「來源/名稱」，不是光禿禿的名字：server 的名字在來源之間不是唯一的
  // （同一個 files 可以在兩個專案裡各有一份，允許目錄還不一樣），
  // 只印名字的話收尾那幾段會指不出是哪一列，而範圍最寬的那一台正好最需要指得準。
  const has = (r, f) => (r[6] || "").split(",").indexOf(f) >= 0;
  const at = (r) => r[0] + "/" + r[3];
  const names = (f) => rows.filter((r) => has(r, f)).map(at);
  const cred = names("cred");
  const unknownCred = names("credunknown");
  const remote = names("remote");
  const wide = names("wide");
  const noscope = rows.filter((r) => r[4] === "unknown").map(at);
  // 明文那一段只算 .mcp.json 那一路：那個檔案預設要進版本庫，
  // 所以「值寫在裡面」的後果跟寫在 ~/.claude.json 裡不是同一件事。
  const inMcpJson = (r) => /^mcp\.json:/.test(r[0] || "");
  const literalInFile = rows.filter((r) => inMcpJson(r) && has(r, "credliteral")).map(at);
  const varInFile = rows.filter((r) => inMcpJson(r) && has(r, "credvar")).map(at);

  if (cred.length) {
    process.stdout.write("\n── 這幾台帶著憑證 ──\n" + cred.join(" ") + "\n");
    process.stdout.write("憑證欄印的是變數名，值一個字都沒印。要看值請自己開設定檔。\n");
  }
  if (literalInFile.length) {
    process.stdout.write("\n── 這幾台的憑證是明文寫在 .mcp.json 裡 ──\n" + literalInFile.join(" ") + "\n");
    process.stdout.write(".mcp.json 是專案範圍那一份，設計上要進版本庫跟團隊共享。\n");
    process.stdout.write("值寫在裡面的意思是它會跟著 git 走出去，而且 git 的歷史刪不掉。\n");
    process.stdout.write("改成 ${VAR} 之後，檔案裡留的是變數名，值留在每個人自己的環境裡。\n");
  }
  if (varInFile.length) {
    process.stdout.write("\n── 這幾台的憑證用 ${VAR}，值不在 .mcp.json 裡 ──\n" + varInFile.join(" ") + "\n");
    process.stdout.write("這是上面那一類的安全寫法。這支不展開它，所以表上印的是變數名不是值。\n");
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
else if (mode === "roots") fromRoots();
else if (mode === "cli") fromCli();
else if (mode === "table") table();
else if (mode === "mask") process.stdout.write(maskInline(fs.readFileSync(0, "utf8")));
else die("用法：node mcp-config.cjs file|roots|cli|table|mask\n", 2);
