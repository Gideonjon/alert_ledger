// Appwrite Function: Alert Ledger API
// POST /ingest       { text } or { alerts: [{ text, sender?, receivedAt? }] }
// POST /ask          { question }
// POST /recategorize { rowId, category, applyToSimilar? }
// POST /delete       { rowId }

import crypto from 'node:crypto';
import * as sdk from 'node-appwrite';
import { IDS } from './config.js';
import { parseAlert } from './parser.js';
import { CATEGORIES, categorizeByKeyword } from './categories.js';
import { parseQuestion } from './question.js';

const { Query, Permission, Role } = sdk;

function services(req) {
  const client = new sdk.Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] || process.env.APPWRITE_API_KEY);

  return { tablesDB: new sdk.TablesDB(client) };
}

function rowIdFor(userId, raw) {
  const normalized = String(raw).replace(/\s+/g, ' ').trim().toUpperCase();
  return crypto.createHash('sha256')
    .update(`${userId}|${normalized}`)
    .digest('hex')
    .slice(0, 32);
}

const naira = (kobo) =>
  `₦${(kobo / 100).toLocaleString('en-NG', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;

export async function ingest({ tablesDB }, userId, body, log = () => {}) {
  const alerts = Array.isArray(body.alerts) ? body.alerts : [body];
  const results = [];

  for (const alert of alerts) {
    const inputText = String(alert?.text || '');

    if (!inputText.trim()) {
      results.push({
        status: 'unparsed',
        reason: 'Transaction alert text is empty',
        text: inputText,
      });
      continue;
    }

    const tx = parseAlert(inputText, alert);

    if (!tx.ok) {
      results.push({
        status: 'unparsed',
        reason: tx.reason,
        text: inputText,
      });
      continue;
    }

    const keywordCategory = categorizeByKeyword(tx.description || inputText);
    tx.category = keywordCategory || 'other';
    tx.categorySource = keywordCategory ? 'keyword' : 'none';

    // A credit described as a transfer is treated as income.
    if (tx.direction === 'credit' && tx.category === 'transfer') {
      tx.category = 'income';
    }

    const rowId = rowIdFor(userId, inputText);

    try {
      const row = await tablesDB.createRow({
        databaseId: IDS.tablesDb,
        tableId: IDS.transactionsTable,
        rowId,
        data: {
          userId,
          direction: tx.direction,
          amountKobo: tx.amountKobo,
          balanceKobo: tx.balanceKobo ?? null,
          description: String(tx.description || inputText).slice(0, 500),
          counterparty: String(tx.counterparty || '').slice(0, 120),
          category: tx.category,
          categorySource: tx.categorySource,
          bank: tx.bank || 'unknown',
          txDate: `${tx.date}T12:00:00.000+00:00`,
          raw: inputText.slice(0, 2000),
        },
        permissions: [
          Permission.read(Role.user(userId)),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
        ],
      });

      results.push({ status: 'created', row });
    } catch (e) {
      if (e.code === 409) {
        results.push({ status: 'duplicate', rowId });
      } else {
        log(`ingest error: ${e.message}`);
        results.push({ status: 'error', message: e.message });
      }
    }
  }

  return { results };
}

async function listRowsAll(tablesDB, queries = [], max = 1000) {
  const rows = [];
  let cursor = null;

  while (rows.length < max) {
    const page = await tablesDB.listRows({
      databaseId: IDS.tablesDb,
      tableId: IDS.transactionsTable,
      queries: [
        ...queries,
        Query.limit(Math.min(100, max - rows.length)),
        ...(cursor ? [Query.cursorAfter(cursor)] : []),
      ],
    });

    rows.push(...page.rows);

    if (page.rows.length < 100) break;
    cursor = page.rows.at(-1).$id;
  }

  return rows.slice(0, max);
}

function normalize(value) {
  return String(value || '').toLowerCase().replace(/\s+/g, ' ').trim();
}

function matchesTopic(row, topic) {
  if (!topic) return true;

  const searchable = normalize([
    row.description,
    row.counterparty,
    row.category?.replace(/_/g, ' '),
    row.bank,
    row.raw,
  ].join(' '));

  const terms = normalize(topic).split(' ').filter(Boolean);

  // Every remaining search term must appear somewhere in the transaction.
  return terms.every((term) => searchable.includes(term));
}

export async function ask({ tablesDB }, userId, question, now = new Date()) {
  const q = parseQuestion(question, now);

  const scope = [Query.equal('userId', [userId])];

  if (q.direction) {
    scope.push(Query.equal('direction', [q.direction]));
  }

  if (q.from && q.to) {
    scope.push(
      Query.between(
        'txDate',
        `${q.from}T00:00:00.000+00:00`,
        `${q.to}T23:59:59.999+00:00`,
      ),
    );
  }

  // Read only the current user's rows, then apply simple text matching.
  let rows = await listRowsAll(tablesDB, scope);

  if (q.category) {
    rows = rows.filter((row) => row.category === q.category);
  }

  if (q.topic) {
    rows = rows.filter((row) => matchesTopic(row, q.topic));
  }

  rows.sort((a, b) => String(b.txDate).localeCompare(String(a.txDate)));

  const totalKobo = rows.reduce(
    (sum, row) => sum + Number(row.amountKobo || 0),
    0,
  );

  const about = q.category
    ? ` on ${q.category.replace(/_/g, ' ')}`
    : q.topic
      ? ` matching "${q.topic}"`
      : '';

  const span = q.from
    ? q.from === q.to
      ? ` on ${q.from}`
      : ` between ${q.from} and ${q.to}`
    : '';

  const verb = q.direction === 'credit'
    ? 'received'
    : q.direction === 'debit'
      ? 'spent'
      : 'moved';

  let answer;

  if (!rows.length) {
    answer = `I couldn't find any transactions${about}${span}.`;
  } else if (q.intent === 'count') {
    answer = `${rows.length} transaction${rows.length === 1 ? '' : 's'}${about}${span}.`;
  } else {
    answer = `You ${verb} ${naira(totalKobo)}${about}${span} across ${rows.length} transaction${rows.length === 1 ? '' : 's'}.`;
  }

  return {
    answer,
    totalKobo,
    count: rows.length,
    parsed: q,
    items: rows.map((row) => ({
      ...row,
      matchedBy: q.category ? 'category' : q.topic ? 'text' : 'range',
      distance: null,
    })),
  };
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function ownedRow(tablesDB, userId, rowId) {
  if (!rowId) throw new HttpError(400, 'rowId is required');

  let row;

  try {
    row = await tablesDB.getRow({
      databaseId: IDS.tablesDb,
      tableId: IDS.transactionsTable,
      rowId,
    });
  } catch (e) {
    if (e.code === 404) {
      throw new HttpError(404, 'Transaction not found');
    }
    throw e;
  }

  if (row.userId !== userId) {
    throw new HttpError(404, 'Transaction not found');
  }

  return row;
}

export async function recategorize(
  { tablesDB },
  userId,
  { rowId, category, applyToSimilar = false },
) {
  if (!CATEGORIES.includes(category)) {
    throw new HttpError(400, `Unknown category: ${category}`);
  }

  const row = await ownedRow(tablesDB, userId, rowId);
  const targets = [row];

  if (applyToSimilar && row.counterparty) {
    const same = await listRowsAll(tablesDB, [
      Query.equal('userId', [userId]),
      Query.equal('counterparty', [row.counterparty]),
    ]);

    targets.push(
      ...same.filter(
        (item) => item.$id !== row.$id && item.category !== category,
      ),
    );
  }

  for (const item of targets) {
    await tablesDB.updateRow({
      databaseId: IDS.tablesDb,
      tableId: IDS.transactionsTable,
      rowId: item.$id,
      data: { category, categorySource: 'user' },
    });
  }

  let similar = 0;

  if (!applyToSimilar && row.counterparty) {
    const same = await listRowsAll(tablesDB, [
      Query.equal('userId', [userId]),
      Query.equal('counterparty', [row.counterparty]),
    ]);

    similar = same.filter(
      (item) => item.$id !== row.$id && item.category !== category,
    ).length;
  }

  return { updated: targets.length, similar };
}

export async function deleteTx({ tablesDB }, userId, { rowId }) {
  await ownedRow(tablesDB, userId, rowId);

  await tablesDB.deleteRow({
    databaseId: IDS.tablesDb,
    tableId: IDS.transactionsTable,
    rowId,
  });

  return { deleted: rowId };
}

export default async ({ req, res, log, error }) => {
  const userId = req.headers['x-appwrite-user-id'];

  if (!userId) {
    return res.json({ error: 'Sign in first' }, 401);
  }

  let body = {};

  try {
    body = typeof req.body === 'string' && req.body
      ? JSON.parse(req.body)
      : req.bodyJson || req.body || {};
  } catch {
    return res.json({ error: 'Invalid JSON body' }, 400);
  }

  const svc = services(req);

  try {
    if (req.method === 'POST' && req.path === '/ingest') {
      return res.json(await ingest(svc, userId, body, log));
    }

    if (req.method === 'POST' && req.path === '/ask') {
      if (!body.question) {
        return res.json({ error: 'question is required' }, 400);
      }
      return res.json(await ask(svc, userId, body.question));
    }

    if (req.method === 'POST' && req.path === '/recategorize') {
      return res.json(await recategorize(svc, userId, body));
    }

    if (req.method === 'POST' && req.path === '/delete') {
      return res.json(await deleteTx(svc, userId, body));
    }

    return res.json({ error: 'Not found' }, 404);
  } catch (e) {
    if (e instanceof HttpError) {
      return res.json({ error: e.message }, e.status);
    }

    error(e.stack || e.message);
    return res.json({ error: e.message || 'Internal server error' }, 500);
  }
};
EOF