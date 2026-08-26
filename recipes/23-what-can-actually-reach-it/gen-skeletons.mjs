// 對 surface.tsv 上標「是」的每一列，生一份測試骨架。
//
//   node gen-skeletons.mjs          # 寫進 skeletons/
//   node gen-skeletons.mjs --check  # 只比對現有的跟該生的一不一樣，不寫檔
//
// 骨架裡沒有 assert 條件，這是故意的。規格把「成功條件由人定」放在 Day 24，
// 理由是定義交出去就變成模型自己出題自己改卷。今天交的是殼：
// 入口、危險動作、目前量到停在哪，以及一個 throw，逼明天的人動手填。
//
// 骨架不進 14/attacks.jsonl。那份是固定攻擊集，Day 24 才動它。
import { readFileSync, writeFileSync, readdirSync, mkdirSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "skeletons");

export function rows() {
  return readFileSync(join(HERE, "surface.tsv"), "utf8")
    .split("\n")
    .filter((l) => l.trim() && !l.startsWith("#") && !l.startsWith("id\t"))
    .map((l) => {
      const [id, entry, how, action, reach, evidence, day24] = l.split("\t");
      return { id, entry, how, action, reach, evidence, day24 };
    });
}

export function skeleton(r) {
  return `// ${r.id}　${r.entry} → ${r.action}
//
// 這份是骨架，Day 24 要填的是成功條件，不是這裡的敘述。
// 今天量到的可達性：${r.reach}
// 依據：${r.evidence}
//
// 明天要回答的兩件事（規格 Day 24 動作 2）：
//   一、這條路徑「必須被擋」還是「擋不住可以接受」
//   二、擋住的判準是什麼（看哪個可觀察的東西，不是看模型講了什麼）
import { test } from "node:test";

test("${r.id} ${r.entry.replace(/"/g, "")}", () => {
  throw new Error("Day 24 要填成功條件。填之前這條測試就沒過，這是設計。");
});
`;
}

const CHECK = process.argv.includes("--check");
const want = new Map(rows().filter((r) => r.day24?.startsWith("是")).map((r) => [`${r.id}.test.mjs`, skeleton(r)]));

if (CHECK) {
  let bad = 0;
  const have = new Set(readdirSync(OUT).filter((f) => f.endsWith(".test.mjs")));
  for (const f of have) if (!want.has(f)) (bad++, console.error(`多了 ${f}，surface.tsv 上沒有它`));
  for (const [f, body] of want) {
    if (!have.has(f)) { bad++; console.error(`少了 ${f}`); continue; }
    if (readFileSync(join(OUT, f), "utf8") !== body) (bad++, console.error(`${f} 跟 surface.tsv 對不上`));
  }
  console.log(bad === 0 ? `${want.size} 份骨架跟 surface.tsv 一致` : `${bad} 份對不上`);
  process.exit(bad === 0 ? 0 : 1);
}

mkdirSync(OUT, { recursive: true });
for (const f of readdirSync(OUT).filter((x) => x.endsWith(".test.mjs"))) {
  if (!want.has(f)) rmSync(join(OUT, f));
}
for (const [f, body] of want) writeFileSync(join(OUT, f), body);
console.log(`寫了 ${want.size} 份骨架到 skeletons/`);
