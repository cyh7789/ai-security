export function formatPrice(cents, currency = "TWD") {
  return new Intl.NumberFormat("zh-TW", {
    style: "currency",
    currency,
  }).format(cents / 100);
}

export function formatDate(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) {
    return "";
  }
  return new Intl.DateTimeFormat("zh-TW", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Taipei",
  }).format(d);
}

export function truncate(text, max = 80) {
  return [...text].length <= max ? text : [...text].slice(0, max).join("") + "…";
}
