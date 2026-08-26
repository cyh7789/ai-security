// cases.tsv 的 node --test 入口。
//
//   node --test cases.test.mjs
//   node --test --test-name-pattern C05 cases.test.mjs
//
// 一個檔而不是一條案例一個檔，理由是「期望」那一欄要人一眼看完。
// recipe 23 交下來的骨架是一條一個檔（23/skeletons/），照那個形狀填的話，
// 「這條必須被擋」會散在九個檔案裡，而規格的【分工】要求的正是人親自看那一欄。
// 散開之後沒有人會把九個檔案排在一起看，於是那一欄實際上沒有被人審過。
// 骨架留在 recipe 23 沒有動，它記的是那一天的產出。
//
// 這裡不重新實作判準。判準只有一份，在 run.sh 裡，
// 兩份的話它們會分岔，而分岔的那天測試還會過。
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));

const cases = readFileSync(join(HERE, "cases.tsv"), "utf8")
  .split("\n")
  .filter((l) => l.trim() && !l.startsWith("#"))
  .slice(1)
  .map((l) => l.split("\t"));

assert.ok(cases.length > 0, "cases.tsv 一條都讀不到");

// 測試名字裡一定要帶狀態。第一版沒帶，跑起來是「12 pass」，
// 而其中六條是已知缺口，那行字跟「十二條全都防住了」逐字相同，
// 也就是這一天要處理的那個錯覺，出現在我自己的產出上。
const state = (want, now) => (want === "擋" && now === "沒擋" ? "缺口" : want === "可接受" ? "選擇不擋" : "擋住");

for (const [id, path, one, , want, , now] of cases) {
  test(`${id}（${path}｜${state(want, now)}）${one}`, () => {
    // run.sh 的離開碼 1 是設計：清單上有已知的缺口。所以這裡不看它的離開碼，
    // 看那一列的「結果」欄。用 execFileSync 的離開碼判會讓每一條都沒過。
    let out;
    try {
      out = execFileSync("bash", [join(HERE, "run.sh"), id], { encoding: "utf8" });
    } catch (e) {
      out = e.stdout ?? "";
    }
    const row = out.split("\n").find((l) => l.startsWith(`${id}\t`));
    assert.ok(row, `run.sh 沒有印出 ${id} 這一列`);
    const [, , gotWant, gotNow, actual, result] = row.split("\t");
    assert.equal(gotWant, want, `${id} 的期望欄跟 cases.tsv 對不上`);
    assert.equal(gotNow, now, `${id} 的紀錄欄跟 cases.tsv 對不上`);
    // 正面表列，不是逐個排除。第一版寫 notEqual(result, "對不上")，
    // 而「對不上」在那之後被拆成四個方向值，run.sh 再也沒印過它，
    // 於是一條真的退步的防線照樣會過。排除式的斷言活不過值域的改動。
    assert.ok(
      ["符合", "缺口"].includes(result),
      `${id} 實測是「${actual}」，紀錄是「${now}」，結果是「${result}」`,
    );
  });
}

// 收尾這一條的名字自己會講話。少了它，上面十二個勾看起來就是十二條防線。
const gaps = cases.filter(([, , , , w, , n]) => w === "擋" && n === "沒擋").length;
const accepted = cases.filter(([, , , , w]) => w === "可接受").length;
test(`收尾：${cases.length} 條裡有 ${gaps} 條是已知缺口、${accepted} 條是選擇不擋，只有 ${cases.length - gaps - accepted} 條真的擋住了`, () => {
  assert.ok(gaps > 0, "一條基線案例都沒有。一份全部通過的攻擊集分不出防得住跟根本沒打到。");
  // 攻擊集固定成檔案這件事，要跟來源對得上才算固定。
  execFileSync("node", [join(HERE, "collect.mjs"), "--check"], { encoding: "utf8" });
});
