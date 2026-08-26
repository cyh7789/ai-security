// 補完的抓取器：字串白名單擋不住 302，這一支擋得住。
//
//   node servers.mjs &                                    # 先把示範服務起起來
//   node safe-fetch.mjs http://127.0.0.1:9011/spec-full
//
// 三層，缺一層就會被繞過：
//   1. 每一跳都重新過那道檢查。自動跟隨重導向等於只檢查第一跳，
//      而 Node 的 fetch 預設就是自動跟隨。
//   2. 名字過了之後，把它解析成位址再檢查一次。
//   3. **拿剛才驗過的那個位址去連**，Host 標頭帶原本的主機名。
//      只做第 2 層不做第 3 層等於白做：檢查完到真正連線之間會再解析一次 DNS，
//      攻擊者控制的網域可以在這兩次之間換掉答案（TOCTOU）。
import { lookup } from "node:dns/promises";
import { fileURLToPath } from "node:url";
import { check, allowlist } from "./gate.mjs";

// 這份示範所有服務都在 127.0.0.1，所以位址層只放行它。
// 真實環境這一組是你那幾台服務的位址，而且要連 IPv6 一起寫。
export const ALLOWED_ADDRESSES = ["127.0.0.1"];

export class Blocked extends Error {
  constructor(reason, url) {
    super(`${reason}（${url}）`);
    this.reason = reason;
    this.url = url;
  }
}

export async function safeFetch(url, opts = {}) {
  const {
    list = allowlist(),
    addresses = ALLOWED_ADDRESSES,
    // 測試會換掉它。真實環境用預設的那個。
    resolve = (host) => lookup(host, { all: true }),
    maxHops = 5,
    fetchImpl = fetch,
  } = opts;

  let current = url;
  const hops = [];
  for (let i = 0; i <= maxHops; i++) {
    const verdict = check(current, list);
    if (!verdict.allow) throw new Blocked(verdict.reason, current);

    const host = new URL(current).hostname;
    const got = await resolve(host);
    const bad = got.filter((a) => !addresses.includes(a.address));
    if (bad.length) {
      throw new Blocked(`${host} 解析到 ${bad.map((a) => a.address).join("、")}`, current);
    }

    // 連的是驗過的那個位址，不是那個名字。https 這樣做會撞 SNI 與憑證主機名，
    // 那種情況要改用能指定 lookup 的傳輸層，這一份只示範 http。
    const u = new URL(current);
    const pinned = new URL(current);
    pinned.hostname = got[0].address;
    const res = await fetchImpl(pinned, {
      redirect: "manual",
      headers: { host: u.host },
    });
    hops.push({ url: current, connected: pinned.toString(), status: res.status });
    if (res.status < 300 || res.status >= 400) return { res, hops };

    const loc = res.headers.get("location");
    if (!loc) throw new Blocked(`${res.status} 但沒有 Location`, current);
    current = new URL(loc, current).toString();
  }
  throw new Blocked(`重導向超過 ${maxHops} 跳`, url);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const { res, hops } = await safeFetch(process.argv[2] ?? "");
    console.log(`allow\t${hops.map((h) => `${h.status} ${h.url}`).join(" → ")}`);
    console.log((await res.text()).trim());
  } catch (e) {
    if (e instanceof Blocked) {
      console.error(`deny\t${e.reason}`);
      process.exit(1);
    }
    // 連不上多半是示範服務沒起來。拋一整頁堆疊沒有幫助。
    if (e?.cause?.code === "ECONNREFUSED") {
      console.error("連不上。先開另一個終端機跑 node servers.mjs，再回來試。");
      process.exit(2);
    }
    throw e;
  }
}
