// ============================================================
// SECTION 02.01 — FORMATTERS
// PURPOSE: Clean display formatting (dates, money, text) for left panel
// ============================================================


export const fmtDate = (v: any) => {
  if (v == null || v === "") return "-";

  // If backend sends DATE as "YYYY-MM-DD" → display as-is (no JS Date parsing)
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v)) return v;

  // If it’s ISO-ish string "YYYY-MM-DDTHH:MM..." → take the date part
  if (typeof v === "string") {
    const m = v.match(/^(\d{4}-\d{2}-\d{2})/);
    if (m) return m[1];
  }

  // Epoch support (if you ever send it)
  if (typeof v === "number") {
    const d = new Date(v);
    const yyyy = d.getUTCFullYear();
    const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
    const dd = String(d.getUTCDate()).padStart(2, "0");
    return `${yyyy}-${mm}-${dd}`;
  }

  return String(v);
};


export const fmtMoney = (v: any) => {
  if (v == null || v === "") return "-";
  const n = typeof v === "string" ? Number(v) : v;
  if (Number.isNaN(n)) return String(v);
  return n.toFixed(2);
};

export const fmtText = (v: any) => {
  if (v == null || v === "") return "-";
  return String(v)
    .replace(/\r\n|\n|\r/g, " ")
    .replace(/\s+/g, " ")
    .trim();
};
