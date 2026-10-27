// Appwrite Function: Alert Ledger API
//   POST /ingest  { text, sender?, receivedAt? }  or  { alerts: [{ text, sender?, receivedAt? }] }
//   POST /ask     { question }
//   POST /recategorize { rowId, category, applyToSimilar? }
//   POST /delete  { rowId }
// Executed by signed-in users; the caller's id comes from x-appwrite-user-id.
import crypto from 'node:crypto';
import * as sdk from 'node-appwrite';
import { IDS } from './config.js';
import { parseAlert } from './parser.js';
import { CATEGORIES, categorizeByKeyword } from './categories.js';
import { parseQuestion } from './question.js';
import { embed, embedTextFor, categorizeByVector, storeTxVector, storeUserSeed, searchTx } from './vector.js';

const { Query, Permission, Role } = sdk;

function services(req) {
  const client = new sdk.Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    // Dynamic key (scopes set in the function's settings), or a project API key as fallback
    .setKey(req.headers['x-appwrite-key'] || process.env.APPWRITE_API_KEY);
  return {
    tablesDB: new sdk.TablesDB(client),
    vectorsDB: new sdk.VectorsDB(client),
    embeddings: new sdk.Embeddings(client),
  };
}

// Same alert pasted twice → same id → second insert is a 409 we treat as "duplicate"
function rowIdFor(userId, raw) {
  const norm = raw.replace(/\s+/g, ' ').trim().toUpperCase();
  return crypto.createHash('sha256').update(`${userId}|${norm}`).digest('hex').slice(0, 32);
}

const naira = (kobo) => `₦${(kobo / 100).toLocaleString('en-NG', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export async function ingest({ tablesDB, vectorsDB, embeddings }, userId, body, log) {
  const alerts = Array.isArray(body.alerts) ? body.alerts : [body];
  const parsed = alerts.map((a) => ({ input: a, tx: parseAlert(a.text, a) }));
  const good = parsed.filter((p) => p.tx.ok);

  // Pass 1: embed the raw descriptions (one call) to categorise unknown merchants
  const needVector = good.filter((p) => !(p.tx.category = categorizeByKeyword(p.tx.description)));
  const descVectors = await embed(embeddings, needVector.map((p) => p.tx.description || p.input.text));
  for (let i = 0; i < needVector.length; i++) {
    const hit = await categorizeByVector(vectorsDB, descVectors[i], userId);
    needVector[i].tx.category = hit ? hit.category : 'other';
    needVector[i].tx.categorySource = hit ? 'vector' : 'none';
  }
  for (const p of good) {
    p.tx.categorySource ||= 'keyword';
    // A transfer from a person reads better as income than "transfer"
    if (p.tx.direction === 'credit' && p.tx.category === 'transfer') p.tx.category = 'income';
  }

  // Pass 2: embed the searchable text (one call) and store row + vector
  const texts = good.map((p) => embedTextFor(p.tx));
  const vectors = await embed(embeddings, texts);
  const results = [];

  for (const p of parsed) {
    if (!p.tx.ok) {
      results.push({ status: 'unparsed', reason: p.tx.reason, text: p.input.text });
      continue;
    }
    const i = good.indexOf(p);
    const rowId = rowIdFor(userId, p.input.text);
    const { tx } = p;
    try {
      const row = await tablesDB.createRow({
        databaseId: IDS.tablesDb,
        tableId: IDS.transactionsTable,
        rowId,
        data: {
          userId,
          direction: tx.direction,
          amountKobo: tx.amountKobo,
          balanceKobo: tx.balanceKobo,
          description: tx.description.slice(0, 500),
          counterparty: tx.counterparty.slice(0, 120),
          category: tx.category,
          categorySource: tx.categorySource,
          bank: tx.bank,
          txDate: `${tx.date}T12:00:00.000+00:00`,
          raw: String(p.input.text).slice(0, 2000),
        },
        permissions: [
          Permission.read(Role.user(userId)),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
        ],
      });
      await storeTxVector(vectorsDB, { rowId, userId, tx, vector: vectors[i], text: texts[i] });
      results.push({ status: 'created', row });
    } catch (e) {
      if (e.code === 409) results.push({ status: 'duplicate', rowId });
      else {
        log(`ingest error: ${e.message}`);
        results.push({ status: 'error', message: e.message });
      }
    }
  }
  return { results };
}

async function listRowsAll(tablesDB, queries, max = 1000) {
  const out = [];
  let cursor = null;
  while (out.length < max) {
    const page = await tablesDB.listRows({
      databaseId: IDS.tablesDb,
      tableId: IDS.transactionsTable,
      queries: [...queries, Query.limit(100), ...(cursor ? [Query.cursorAfter(cursor)] : [])],
    });
    out.push(...page.rows);
    if (page.rows.length < 100) break;
    cursor = page.rows.at(-1).$id;
  }
  return out;
}

export async function ask({ tablesDB, vectorsDB, embeddings }, userId, question, now = new Date()) {
  const q = parseQuestion(question, now);
  const scope = [Query.equal('userId', [userId])];
  if (q.direction) scope.push(Query.equal('direction', [q.direction]));
  if (q.from) scope.push(Query.between('txDate', `${q.from}T00:00:00.000+00:00`, `${q.to}T23:59:59.999+00:00`));

  const matched = new Map(); // rowId -> { by, distance? }
  const topicIsJustCategory = q.category && q.topic.split(' ').length <= 1;

  // Exact path: TablesDB filter on the category column
  if (q.category) {
    const rows = await listRowsAll(tablesDB, [...scope, Query.equal('category', [q.category])]);
    for (const r of rows) matched.set(r.$id, { by: 'category', row: r });
  }

  // Meaning path: VectorsDB similarity for names, merchants and vague words
  if (q.topic && !topicIsJustCategory) {
    const [vector] = await embed(embeddings, [q.topic]);
    const hits = await searchTx(vectorsDB, { userId, vector, from: q.from, to: q.to, direction: q.direction });
    const missing = hits.filter((h) => !matched.has(h.rowId));
    if (missing.length) {
      const rows = await listRowsAll(tablesDB, [Query.equal('$id', missing.map((h) => h.rowId))]);
      const byId = new Map(rows.map((r) => [r.$id, r]));
      for (const h of missing) if (byId.has(h.rowId)) matched.set(h.rowId, { by: 'meaning', distance: h.distance, row: byId.get(h.rowId) });
    }
  }

  // No topic at all ("how much did I spend last month") → everything in scope
  if (!q.category && !q.topic) {
    for (const r of await listRowsAll(tablesDB, scope)) matched.set(r.$id, { by: 'range', row: r });
  }

  const items = [...matched.values()].sort((a, b) => b.row.txDate.localeCompare(a.row.txDate));
  const totalKobo = items.reduce((s, m) => s + m.row.amountKobo, 0);
  const verb = q.direction === 'credit' ? 'received' : q.direction === 'debit' ? 'spent' : 'moved';
  const span = q.from ? (q.from === q.to ? ` on ${q.from}` : ` between ${q.from} and ${q.to}`) : '';
  const about = q.category ? ` on ${q.category.replace('_', ' ')}` : q.topic ? ` matching "${q.topic}"` : '';

  let answer;
  if (!items.length) answer = `I couldn't find any transactions${about}${span}.`;
  else if (q.intent === 'count') answer = `${items.length} transaction${items.length === 1 ? '' : 's'}${about}${span}.`;
  else answer = `You ${verb} ${naira(totalKobo)}${about}${span} across ${items.length} transaction${items.length === 1 ? '' : 's'}.`;

  return {
    answer,
    totalKobo,
    count: items.length,
    parsed: q, // shown in the app so judges can see how the question was understood
    items: items.map((m) => ({ ...m.row, matchedBy: m.by, distance: m.distance ?? null })),
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
    row = await tablesDB.getRow({ databaseId: IDS.tablesDb, tableId: IDS.transactionsTable, rowId });
  } catch (e) {
    if (e.code === 404) throw new HttpError(404, 'Transaction not found');
    throw e;
  }
  if (row.userId !== userId) throw new HttpError(404, 'Transaction not found');
  return row;
}

const ignore404 = (p) => p.catch((e) => { if (e.code !== 404) throw e; });

/**
 * Fix a transaction's category. The correction also becomes a personal example in
 * VectorsDB, so future alerts from similar merchants land in the right category.
 * With applyToSimilar, other rows with the same counterparty are updated too.
 */
export async function recategorize({ tablesDB, vectorsDB, embeddings }, userId, { rowId, category, applyToSimilar = false }) {
  if (!CATEGORIES.includes(category)) throw new HttpError(400, `Unknown category: ${category}`);
  const row = await ownedRow(tablesDB, userId, rowId);

  const targets = [row];
  if (applyToSimilar && row.counterparty) {
    const same = await listRowsAll(tablesDB, [
      Query.equal('userId', [userId]),
      Query.equal('counterparty', [row.counterparty]),
    ]);
    targets.push(...same.filter((r) => r.$id !== row.$id && r.category !== category));
  }

  for (const r of targets) {
    await tablesDB.updateRow({
      databaseId: IDS.tablesDb,
      tableId: IDS.transactionsTable,
      rowId: r.$id,
      data: { category, categorySource: 'user' },
    });
    const tx = { direction: r.direction, description: r.description, counterparty: r.counterparty, category, date: r.txDate.slice(0, 10) };
    const text = embedTextFor(tx);
    const [vector] = await embed(embeddings, [text]);
    // Re-store the transaction vector so its metadata.category and text stay in sync
    await ignore404(vectorsDB.deleteDocument({ databaseId: IDS.vectorsDb, collectionId: IDS.txVectors, documentId: r.$id }));
    await storeTxVector(vectorsDB, { rowId: r.$id, userId, tx, vector, text });
  }

  const [seedVector] = await embed(embeddings, [row.description || row.counterparty]);
  await storeUserSeed(vectorsDB, { userId, rowId: row.$id, category, text: row.description || row.counterparty, vector: seedVector });

  let similar = 0;
  if (!applyToSimilar && row.counterparty) {
    const same = await listRowsAll(tablesDB, [
      Query.equal('userId', [userId]),
      Query.equal('counterparty', [row.counterparty]),
    ]);
    similar = same.filter((r) => r.$id !== row.$id && r.category !== category).length;
  }
  return { updated: targets.length, similar };
}

/** Delete a transaction everywhere it lives: the row, its vector and any seed it taught. */
export async function deleteTx({ tablesDB, vectorsDB }, userId, { rowId }) {
  await ownedRow(tablesDB, userId, rowId);
  await tablesDB.deleteRow({ databaseId: IDS.tablesDb, tableId: IDS.transactionsTable, rowId });
  await ignore404(vectorsDB.deleteDocument({ databaseId: IDS.vectorsDb, collectionId: IDS.txVectors, documentId: rowId }));
  await ignore404(vectorsDB.deleteDocument({ databaseId: IDS.vectorsDb, collectionId: IDS.categorySeeds, documentId: `s${rowId}` }));
  return { deleted: rowId };
}

export default async ({ req, res, log, error }) => {
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return res.json({ error: 'Sign in first' }, 401);

  let body = {};
  try {
    body = typeof req.body === 'string' && req.body ? JSON.parse(req.body) : req.bodyJson || req.body || {};
  } catch {
    return res.json({ error: 'Invalid JSON body' }, 400);
  }

  const svc = services(req);
  try {
    if (req.method === 'POST' && req.path === '/ingest') {
      return res.json(await ingest(svc, userId, body, log));
    }
    if (req.method === 'POST' && req.path === '/ask') {
      if (!body.question) return res.json({ error: 'question is required' }, 400);
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
    if (e instanceof HttpError) return res.json({ error: e.message }, e.status);
    error(e.stack || e.message);
    return res.json({ error: e.message }, 500);
  }
};
