/** 回傳 dump 那一行。device 由呼叫端提供。 */
export function inspectDevice(device) {
  return `dump ${device}`.trim();
}
