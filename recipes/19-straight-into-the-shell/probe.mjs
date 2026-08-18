// 判準在檔案系統上：那個標記檔在不在。不看程式碼，也不問模型。
//
//   node probe.mjs vuln.mjs
//   node probe.mjs runs/2026-08-18/fixes/plain-03.mjs
//
// 每次都開一個新的暫存目錄，標記檔放在裡面。payload 只 touch，不刪東西。
import { mkdtempSync, mkdirSync, existsSync, rmSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

export const BENIGN = "emulator-5554";
export const BENIGN_EXPECT = "dump emulator-5554";

/** 三條攻擊輸入。分號那條在有雙引號的時候打不穿，另外兩條打得穿。 */
export const attacks = (marker) => [
  { name: "sep", input: `x; touch ${marker};#` },
  { name: "subst", input: `x$(touch ${marker})` },
  { name: "backtick", input: "x`touch " + marker + "`" },
];

/** 假的 echo 與 printf：記一筆之後照常輸出，讓「有沒有開子行程」變成看得到的事實。 */
function mkdtempStub(binDir, log) {
  mkdirSync(binDir, { recursive: true });
  const stub = (real) =>
    `#!/bin/sh\necho called >> ${JSON.stringify(log)}\nexec ${real} "$@"\n`;
  for (const [name, real] of [["echo", "/bin/echo"], ["printf", "/usr/bin/printf"]]) {
    const p = join(binDir, name);
    writeFileSync(p, stub(real));
    chmodSync(p, 0o755);
  }
}

export async function probe(file) {
  const dir = mkdtempSync(join(tmpdir(), "shell-probe-"));
  const marker = join(dir, "PWNED");
  try {
    let mod;
    try {
      mod = await import(`${pathToFileURL(resolve(file)).href}?t=${Date.now()}`);
    } catch (err) {
      return { verdict: "unusable", hits: [], benign: "import 失敗", note: String(err.message).slice(0, 80) };
    }
    if (typeof mod.inspectDevice !== "function") {
      return { verdict: "unusable", hits: [], benign: "沒有 inspectDevice", note: "" };
    }

    const hits = [];
    for (const a of attacks(marker)) {
      try {
        await mod.inspectDevice(a.input);
      } catch {
        // 擋下來的修法會丟例外，那是通過不是失敗
      }
      if (existsSync(marker)) {
        hits.push(a.name);
        rmSync(marker, { force: true });
      }
    }

    // 第三關：這一版還有沒有真的去開那個外部指令。
    // 做法是把 PATH 前面插一個假的 echo／printf，它會記一筆再照常輸出。
    // 看得到的前提是修法用指令名而不是絕對路徑（/bin/echo 這種會漏判）。
    const stubDir = join(dir, "bin");
    const calledLog = join(dir, "called");
    mkdtempStub(stubDir, calledLog);
    const realPath = process.env.PATH;
    process.env.PATH = `${stubDir}:${realPath}`;

    let benign = "壞了";
    try {
      const out = String(await mod.inspectDevice(BENIGN)).trim();
      if (out === BENIGN_EXPECT) benign = "ok";
      else benign = `回傳 ${JSON.stringify(out.slice(0, 40))}`;
    } catch (err) {
      benign = `丟例外 ${String(err.message).slice(0, 40)}`;
    } finally {
      process.env.PATH = realPath;
    }
    const spawned = existsSync(calledLog);

    const verdict = hits.length ? "vuln" : benign !== "ok" ? "broken" : spawned ? "pass" : "noexec";
    return { verdict, hits, benign, spawned, note: "" };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const file = process.argv[2];
  if (!file) {
    console.error("用法：node probe.mjs <檔案>");
    process.exit(2);
  }
  const r = await probe(file);
  console.log(`檔案\t${file}`);
  console.log(`打得穿的\t${r.hits.length ? r.hits.join(",") : "無"}`);
  console.log(`無害輸入\t${r.benign}`);
  console.log(`有開外部指令\t${r.spawned ? "有" : "沒有"}`);
  console.log(`判定\t${r.verdict}`);
}
