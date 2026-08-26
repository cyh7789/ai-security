// 兩個判斷點的接線。判斷邏輯一行都沒有搬過來，這裡只做三件事：
// 呼叫原本那道檢查、算出當時的判準版本、把結果寫成一行紀錄。
//
// 為什麼直接 import 前幾天的檔案，而不是複製一份過來：
// 複製的那一份會跟本尊漂開，而漂開的當下沒有任何徵兆：紀錄照樣一行行寫出來，
// 只是它記的判準已經不是線上那一版。這種錯事後看不出來。
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { LIMITS, OUT_OF_SCOPE, SCENARIO, scenarioGate } from "../18-not-a-free-chatgpt/gates.mjs";
import { DENY_BY_DEFAULT, TARGET_ALLOWLIST, TOOL_ALLOWLIST, WORDS, externalGate } from "../17-words-into-actions/gate.mjs";
import { digest, policyVersion, record } from "./journal.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

// 版本雜湊涵蓋的是「判準的資料」，不是判準的程式碼。
//
// 這個分界要講清楚，因為它決定了這個號碼什麼時候會騙你：
// 清單裡加一個詞、上限從 20 改成 50，號碼會變；
// 而 scenarioGate 裡黑名單與允許清單的先後順序對調，資料一個字都沒動，號碼不變。
// 後面那種改動一樣會讓判決反過來。
//
// 所以下面順手把兩個判斷點的原始碼也餵進去。程式碼變、號碼就變，
// 代價是連改個註解都會換版本，好處是不會有「判準變了而紀錄沒發現」的那種漏。
// 兩種都做不到完美：只吃資料會漏改邏輯，連程式碼一起吃會多出假變動。
// 選後者是因為多一次假變動只是多看一眼，漏一次真變動是整批統計作廢。
const src = (p) => readFileSync(join(HERE, p), "utf8");

export const INPUT_POINT = "input-gate";
export const ACTION_POINT = "action-gate";

export const INPUT_VERSION = policyVersion(SCENARIO, OUT_OF_SCOPE, LIMITS, src("../18-not-a-free-chatgpt/gates.mjs"));
export const ACTION_VERSION = policyVersion(
  DENY_BY_DEFAULT,
  TOOL_ALLOWLIST,
  TARGET_ALLOWLIST,
  WORDS,
  src("../17-words-into-actions/gate.mjs"),
);

// 擋跟放都記。
//
// 只記擋下來的那些是最省事的做法，也是這件事最常見的做法，而它剛好把
// 「漏網」整類問題變成看不見：一筆該擋沒擋的請求，在只記 deny 的紀錄裡
// 連一行都不會出現。你翻遍紀錄找不到它，不是因為它不存在，是因為你沒記。
export function checkInput(text, traceId) {
  const r = scenarioGate(text);
  record({
    trace_id: traceId,
    point: INPUT_POINT,
    policy_version: INPUT_VERSION,
    digest: digest(text),
    decision: r.allow ? "allow" : "deny",
    reason_code: r.code,
    reason_text: r.reason,
  });
  return r;
}

export function checkAction(call, userRequest, traceId) {
  const r = externalGate(call, userRequest);
  record({
    trace_id: traceId,
    point: ACTION_POINT,
    policy_version: ACTION_VERSION,
    digest: digest(`${call.tool}:${JSON.stringify(call.args ?? {})}|${userRequest}`),
    decision: r.allow ? "allow" : "deny",
    reason_code: r.code,
    reason_text: r.reason,
  });
  return r;
}
