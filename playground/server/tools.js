const { exec } = require("child_process");
const util = require("util");
const execAsync = util.promisify(exec);

// 讓模型可以呼叫的工具：查一個網域的 DNS 紀錄
async function lookupDomain(domain) {
  const { stdout } = await execAsync(`dig +short ${domain}`);
  return stdout.trim();
}

// 讓模型可以呼叫的工具：把使用者上傳的圖轉成縮圖
async function makeThumbnail(filename) {
  const { stdout } = await execAsync(
    `convert uploads/${filename} -resize 200x200 thumbs/${filename}`
  );
  return stdout;
}

module.exports = { lookupDomain, makeThumbnail };
