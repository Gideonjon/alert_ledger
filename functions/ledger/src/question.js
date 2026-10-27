// Turns a plain-English question into: intent, direction, date range, category, topic.
// Deterministic on purpose: the vector search handles the fuzzy part (topic),
// and sums are computed from TablesDB rows, so totals are never "hallucinated".
import { categoryFromWords } from './categories.js';

const MONTH_NAMES = ['january', 'february', 'march', 'april', 'may', 'june', 'july',
  'august', 'september', 'october', 'november', 'december'];
const MONTH_SHORT = MONTH_NAMES.map((m) => m.slice(0, 3));

const STOP = new Set(`how much did i do we spend spent spending on in for the a an of my me
what was is are were total show list find all any get give tell transactions transaction
payments payment money last this past days day weeks week months month year today yesterday
between and from to between since ago naira ngn have has much many times did paid pay
receive received got get credit credits debit debits sent send transfers transfer
where go went goes buy bought it i've ive so far`
  .split(/\s+/));

const ymd = (d) => d.toISOString().slice(0, 10);
const utc = (y, m, d) => new Date(Date.UTC(y, m, d));
const lastDay = (y, m) => utc(y, m + 1, 0).getUTCDate();

function monthRange(y, m) {
  return [ymd(utc(y, m, 1)), ymd(utc(y, m, lastDay(y, m)))];
}

export function parseRange(q, now = new Date()) {
  const y = now.getUTCFullYear();
  const mo = now.getUTCMonth();
  const today = utc(y, mo, now.getUTCDate());
  let m;

  if (/\btoday\b/.test(q)) return [ymd(today), ymd(today)];
  if (/\byesterday\b/.test(q)) {
    const d = new Date(today); d.setUTCDate(d.getUTCDate() - 1);
    return [ymd(d), ymd(d)];
  }
  if ((m = q.match(/\b(?:last|past)\s+(\d{1,3})\s+days?\b/))) {
    const d = new Date(today); d.setUTCDate(d.getUTCDate() - (+m[1] - 1));
    return [ymd(d), ymd(today)];
  }
  if (/\b(this|current)\s+week\b/.test(q)) {
    const d = new Date(today); d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
    return [ymd(d), ymd(today)];
  }
  if (/\blast\s+week\b/.test(q)) {
    const start = new Date(today); start.setUTCDate(start.getUTCDate() - ((start.getUTCDay() + 6) % 7) - 7);
    const end = new Date(start); end.setUTCDate(end.getUTCDate() + 6);
    return [ymd(start), ymd(end)];
  }
  if (/\b(this|current)\s+month\b/.test(q)) return [ymd(utc(y, mo, 1)), ymd(today)];
  if (/\blast\s+month\b/.test(q)) return mo === 0 ? monthRange(y - 1, 11) : monthRange(y, mo - 1);
  if (/\bthis\s+year\b/.test(q)) return [`${y}-01-01`, ymd(today)];
  if (/\blast\s+year\b/.test(q)) return [`${y - 1}-01-01`, `${y - 1}-12-31`];

  // "in September", "september 2026", "sept"
  for (let i = 0; i < 12; i++) {
    const re = new RegExp(`\\b(${MONTH_NAMES[i]}|${MONTH_SHORT[i]}t?)\\b(?:\\s+(20\\d{2}))?`);
    if ((m = q.match(re))) {
      let year = m[2] ? +m[2] : y;
      if (!m[2] && i > mo) year -= 1; // "December" asked in October means last December
      return monthRange(year, i);
    }
  }
  if ((m = q.match(/\b(?:in\s+)?(20\d{2})\b/))) return [`${m[1]}-01-01`, `${m[1]}-12-31`];
  return [null, null];
}

export function parseQuestion(question, now = new Date()) {
  const q = ` ${String(question).toLowerCase().replace(/[?!.,]/g, ' ')} `.replace(/\s+/g, ' ');

  let direction = null;
  if (/\b(receive|received|earn|earned|income|credited|credit|came in|got paid|inflow)\b/.test(q)) direction = 'credit';
  else if (/\b(spend|spent|spending|pay|paid|send|sent|transfer|transfers|debit|debited|bought|buy|outflow)\b|\bmoney (go|went)\b/.test(q)) direction = 'debit';

  let intent = 'list';
  if (/\bhow much\b|\btotal\b|\bsum\b/.test(q)) intent = 'sum';
  else if (/\bhow many\b|\bcount\b/.test(q)) intent = 'count';

  const [from, to] = parseRange(q, now);
  const category = categoryFromWords(q);

  const topic = q
    .replace(/\b(?:last|past)\s+\d+\s+days?\b/g, ' ')
    .replace(new RegExp(`\\b(${MONTH_NAMES.join('|')}|${MONTH_SHORT.join('|')}|sept)\\b`, 'g'), ' ')
    .replace(/\b20\d{2}\b|\b\d+\b/g, ' ')
    .split(' ')
    .filter((w) => w && !STOP.has(w))
    .join(' ')
    .trim();

  return { intent, direction, from, to, category, topic };
}
