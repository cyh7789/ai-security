// 判斷點的紀錄器。一個判斷點做完決定，就寫一行進來。
//
// 欄位七個，少一個都會讓事後那份統計失去意義：
//
//   ts             什麼時候
//   trace_id       同一次請求的識別碼。少了它，input-gate 那一列跟 action-gate
//                  那一列就對不起來：兩道閘的 digest 算的是不同東西（一個是輸入
//                  文字，一個是工具加參數），而就算兩邊都雜湊同一段文字，
//                  兩個人同時送一模一樣的字也會拿到同一個 digest。
//                  這一欄不是可選的（8/19 外審抓到，原本七欄沒有它）
//   schema_version 這張表自己的版本。前半篇整篇在講欄位會長，
//                  新表當然要自己標，不然兩週後同一個坑再踩一次
//   point          哪一個判斷點（同一個系統有好幾個，混在一起數就白數了）
//   policy_version 當時那個判斷點用的判準是哪一版
//   digest         輸入的指紋，不是輸入本身（見下面「不記什麼」）
//   decision       allow / deny，放的也要記
//   reason_code    機器產生、可以直接計數的短碼
//   reason_text    人看的自由文字，只給人覆核用
//
// reason 為什麼要拆成兩欄，是這個 recipe 的主張，理由寫在 README。
// 一句話版本：同一個判斷、同一批輸入，模型每次會用不同的措辭寫理由，
// 拿那一欄去做分佈統計，你數到的是它的措辭抖動。
import { createHash } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
export const JOURNAL = join(HERE, "journal.tsv");
export const SCHEMA_VERSION = "1";
export const COLUMNS = [
  "ts", "trace_id", "schema_version", "point", "policy_version",
  "digest", "decision", "reason_code", "reason_text",
];

// 判準版本不是手填的。
//
// 手填的版本號會漏，而且漏的方式很特別：你改判準的當下想的是判準，不是版本號，
// 所以漏掉的那次剛好就是判準真的變了那次。事後你看到那批紀錄都掛同一版，
// 會以為那是同一把尺量出來的。
//
// 所以拿判準本身算雜湊。判準的定義改一個字，這個數字就變，不必記得改它。
export function policyVersion(...definitions) {
  const h = createHash("sha256");
  for (const d of definitions) h.update(JSON.stringify(d));
  return h.digest("hex").slice(0, 8);
}

// 輸入不整段留。留一個指紋，加上長度與前幾個字，足夠讓人事後認出「就是這一筆」，
// 也足夠把重複的輸入歸在一起。
//
// 這是 Day 18 欠下的那條：你為了看清楚防線，在自己的伺服器上多存了一份使用者輸入。
// 那份東西保存多久、誰看得到、刪不刪得掉，是動手之前就要決定的事，不是之後再說。
// 這裡的預設是「留得剛好夠追查，不留全文」，保存期見 README 的那一行。
export function digest(text) {
  const s = String(text);
  const h = createHash("sha256").update(s).digest("hex").slice(0, 10);
  return `${h}:${[...s].length}`;
}

// JOURNAL_NOW 是給驗證用的：時間戳是這張表裡唯一每次都不一樣的欄位，
// 不把它釘住的話，「連跑兩次結果一致」這條就驗不了，而那條是紀錄能不能拿來
// 比對版本差異的前提。
export function record(entry) {
  const row = { ts: process.env.JOURNAL_NOW || new Date().toISOString(), schema_version: SCHEMA_VERSION, ...entry };
  for (const c of COLUMNS) {
    if (row[c] === undefined || row[c] === "") row[c] = "-";
    // 值裡面有 tab 或換行，整個檔的欄位就錯位了，而錯位之後每一欄都還讀得出東西，
    // 不會噴錯。理由那欄是模型寫的，這件事遲早會發生。
    row[c] = String(row[c]).replace(/[\t\r\n]+/g, " ");
  }
  appendFileSync(JOURNAL, COLUMNS.map((c) => row[c]).join("\t") + "\n");
  return row;
}

export function readJournal(path = JOURNAL) {
  const lines = readFileSync(path, "utf8").trim().split("\n").filter(Boolean);
  const head = lines[0].split("\t");
  return lines.slice(1).map((l) => Object.fromEntries(l.split("\t").map((v, i) => [head[i], v])));
}

export function header() {
  return COLUMNS.join("\t") + "\n";
}
