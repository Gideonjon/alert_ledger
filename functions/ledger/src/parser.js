// Parses Nigerian bank / fintech alert text (SMS, email or push notification)
// into a structured transaction. Pure function: no Appwrite calls, easy to test.

const MONTHS = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12,
};

const BANKS = [
  ['gtbank', /\b(gtbank|gtb|guaranty trust)\b/i],
  ['access', /\baccess\s*bank\b|\baccess\b/i],
  ['zenith', /zenith/i],
  ['firstbank', /\b(first\s*bank|firstbank|fbn)\b/i],
  ['uba', /\buba\b|united bank for africa/i],
  ['opay', /\bopay\b/i],
  ['moniepoint', /\bmoniepoint\b/i],
  ['kuda', /\bkuda\b/i],
  ['palmpay', /\bpalmpay\b/i],
  ['wema', /\b(wema|alat)\b/i],
  ['fidelity', /\bfidelity\b/i],
  ['sterling', /\bsterling\b/i],
  ['fcmb', /\bfcmb\b/i],
  ['stanbic', /\bstanbic\b/i],
  ['union', /\bunion\s*bank\b/i],
];

// Matches 5,000.00 / 5000 / 1,234,567.89, optionally prefixed with NGN, N or ₦
const AMOUNT = String.raw`(?:NGN|N|₦)?\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)`;

function toKobo(str) {
  const n = Number(String(str).replace(/,/g, ''));
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100);
}

function pad(n) {
  return String(n).padStart(2, '0');
}

function isoDate(y, m, d) {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return `${y}-${pad(m)}-${pad(d)}`;
}

export function detectBank(text, sender = '') {
  // The sender ID is the most reliable signal; the body can mention other banks
  // (e.g. a Zenith alert for a transfer to a Moniepoint account).
  for (const hay of [sender, text]) {
    if (!hay) continue;
    for (const [name, re] of BANKS) if (re.test(hay)) return name;
  }
  return 'unknown';
}

export function parseDate(text) {
  let m;
  // 2026-10-05
  if ((m = text.match(/\b(20\d{2})-(\d{1,2})-(\d{1,2})\b/))) {
    return isoDate(+m[1], +m[2], +m[3]);
  }
  // 05-OCT-2026 / 05 Oct 2026 / 05-Oct-26
  if ((m = text.match(/\b(\d{1,2})[-\s/]([A-Za-z]{3,4})[-\s/,]+(\d{2,4})\b/))) {
    const mon = MONTHS[m[2].toLowerCase()];
    if (mon) return isoDate(+m[3], mon, +m[1]);
  }
  // 05/10/2026 or 05-10-2026 (Nigerian banks use DD/MM/YYYY)
  if ((m = text.match(/\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b/))) {
    return isoDate(+m[3], +m[2], +m[1]);
  }
  return null;
}

export function parseDirection(text) {
  const t = text.toUpperCase();
  // Explicit labels win
  if (/\b(TXN|TYPE)\s*:\s*DEBIT\b|\bDR\s*AMT\b|\bAMT\s*:?\s*(NGN|N|₦)?\s?[\d,.]+\s*DR\b|^\s*DEBIT\b/m.test(t)) return 'debit';
  if (/\b(TXN|TYPE)\s*:\s*CREDIT\b|\bCR\s*AMT\b|\bAMT\s*:?\s*(NGN|N|₦)?\s?[\d,.]+\s*CR\b|^\s*CREDIT\b/m.test(t)) return 'credit';
  if (/\b(RECEIVED|CREDITED|DEPOSIT|INFLOW)\b|\bCR\b/.test(t)) return 'credit';
  if (/\b(DEBIT|DEBITED|SENT|TRANSFER OF|PURCHASE|WITHDRAWAL|PAID|PAYMENT)\b|\bDR\b/.test(t)) return 'debit';
  return null;
}

function stripBalances(text) {
  // Remove "Avail Bal: NGN45,210.33", "Bal: 12,000", "Balance: ₦..." so they don't get read as the amount
  return text.replace(new RegExp(String.raw`(avail(able)?\.?\s*)?(bal(ance)?|clr\s*bal|ledger\s*bal)\.?\s*:?\s*` + AMOUNT, 'gi'), ' ');
}

export function parseBalance(text) {
  const m = text.match(new RegExp(String.raw`(?:avail(?:able)?\.?\s*)?bal(?:ance)?\.?\s*:?\s*` + AMOUNT, 'i'));
  return m ? toKobo(m[1]) : null;
}

export function parseAmount(text) {
  const t = stripBalances(text);
  const labelled = t.match(new RegExp(String.raw`\b(?:amt|amount|(?:dr|cr)\s*amt)\s*:?\s*` + AMOUNT, 'i'));
  if (labelled) return toKobo(labelled[1]);
  const currency = t.match(/(?:NGN|₦)\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)/i);
  if (currency) return toKobo(currency[1]);
  return null;
}

export function parseDescription(text) {
  let m;
  if ((m = text.match(/\b(?:desc|des|narration|narr|remark|details?)\s*:\s*(.+)/i))) return m[1].trim();
  if ((m = text.match(/\bby\s+(.+?)(?:\.\s*bal|\.\s*avail|$)/im))) return m[1].trim();
  if ((m = text.match(/\b(?:received|sent|paid|transfer(?:red)?)\b.*?\b(?:from|to)\s+(.+?)(?:\s+(?:successful|was|has|on)\b|[.!]|$)/im))) {
    return m[0].replace(/\s+(?:successful|was|has|on)$|[.!]$/i, '').trim();
  }
  // Zenith-style: a bare narration line such as "NIP/MONIEPOINT/EMEKA OKAFOR"
  const bare = text.split(/\n/).map((l) => l.trim()).find((l) => /[A-Z]{3,}\/[A-Z]/.test(l) && !/:/.test(l));
  if (bare) return bare;
  return '';
}

export function parseCounterparty(desc) {
  if (!desc) return '';
  let m;
  // Card/POS purchases: the merchant is what's left after the channel words
  if (/\b(POS|WEB)\b|\bPURCHASE\b/i.test(desc)) {
    return desc
      .replace(/\b(POS|WEB|PURCHASE|PMT|PAYMENT)\b/gi, ' ')
      .replace(/[\/]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .toUpperCase();
  }
  if ((m = desc.match(/\b(?:to|from)\s+([A-Z][A-Z .'-]{2,40}?)(?:\s+(?:successful|was|has|on|via|ref)\b|[\/.!,]|$)/i))) {
    return m[1].trim().toUpperCase();
  }
  // NIP/BANK/NAME or TRF/NAME/REF patterns: take the last chunk with letters and a space
  const parts = desc.split('/').map((p) => p.trim()).filter(Boolean);
  const named = [...parts].reverse().find((p) => /^[A-Za-z][A-Za-z .'-]+\s[A-Za-z .'-]+$/.test(p));
  return named ? named.toUpperCase() : '';
}

/**
 * @param {string} raw    alert text
 * @param {object} opts   { sender?: string, receivedAt?: string (ISO) }
 */
export function parseAlert(raw, opts = {}) {
  const text = String(raw || '').replace(/\r/g, '').trim();
  if (!text) return { ok: false, reason: 'empty' };

  const amountKobo = parseAmount(text);
  const direction = parseDirection(text);
  if (amountKobo == null || !direction) {
    return { ok: false, reason: amountKobo == null ? 'no_amount' : 'no_direction' };
  }

  const description = parseDescription(text);
  const fallbackDate = opts.receivedAt ? opts.receivedAt.slice(0, 10) : new Date().toISOString().slice(0, 10);

  return {
    ok: true,
    direction,
    amountKobo,
    balanceKobo: parseBalance(text),
    description,
    counterparty: parseCounterparty(description),
    date: parseDate(text) || fallbackDate,
    bank: detectBank(text, opts.sender),
  };
}
