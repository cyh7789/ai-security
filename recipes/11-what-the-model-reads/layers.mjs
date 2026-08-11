// 同一份內容的四種「讀法」。這支是純字串運算，沒有副作用，所以驗得動。
//
//   raw     原始檔直接進 prompt（README、原始碼、Markdown、貼上來的整份 HTML）
//   text    去標籤（大多數抓取程式停在這裡）
//   visible 照樣式把畫面上不顯示的丟掉（已經比多數專案講究）
//   human   人真的看得到的字（再拿掉不佔位置的碼點）
//
// visible 是示範用的簡化版：只看行內 style、只認葉節點，不算繼承也不跑排版。
// 真的要判準，要嘛開一顆瀏覽器，要嘛承認你判不準。

export const TAG_BASE = 0xe0000;
export const isGhost = (p) => p >= TAG_BASE && p <= TAG_BASE + 0x7f;

export const stripInvisible = (s) => [...s].filter((c) => !isGhost(c.codePointAt(0))).join("");

export const decodeInvisible = (s) =>
  [...s]
    .map((c) => {
      const p = c.codePointAt(0);
      return isGhost(p) ? String.fromCharCode(p - TAG_BASE) : c;
    })
    .join("");

const unescape = (s) =>
  s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&");

const tidy = (s) => s.replace(/[ \t]+/g, " ").replace(/\s*\n\s*/g, "\n").trim();
const dropTags = (h) => tidy(unescape(h.replace(/<[^>]+>/g, "\n")));

const HIDDEN_STYLE = /style="[^"]*(display\s*:\s*none|visibility\s*:\s*hidden|color\s*:\s*#f{3,6}\b)/i;

export const NAMES = ["raw", "text", "visible", "human"];
export const LABEL = { raw: "原始檔", text: "去標籤", visible: "照樣式篩過", human: "人眼看得到" };

export function layers(html) {
  const noScript = html.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, " ");
  const noComment = noScript.replace(/<!--[\s\S]*?-->/g, " ");
  const noHidden = noComment.replace(/<(\w+)\b[^>]*>[^<]*<\/\1>/gi, (m) =>
    HIDDEN_STYLE.test(m.slice(0, m.indexOf(">") + 1)) ? " " : m,
  );
  const visible = dropTags(noHidden);
  return { raw: html, text: dropTags(noComment), visible, human: stripInvisible(visible) };
}
