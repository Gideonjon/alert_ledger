// End-to-end test of ingest + ask against in-memory fakes of TablesDB, VectorsDB
// and Embeddings. The fake embedder is a hashed bag-of-words, which is crude but
// enough to prove the wiring: names and merchants land near each other.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ingest, ask, recategorize, deleteTx } from '../src/main.js';
import { SEED_EXAMPLES } from '../src/categories.js';
import { fixtures } from './fixtures.js';

const DIM = 768;
function fakeEmbed(text) {
  const v = new Array(DIM).fill(0);
  for (const w of String(text).toLowerCase().match(/[a-z]{3,}/g) || []) {
    let h = 0;
    for (const c of w) h = (h * 31 + c.charCodeAt(0)) >>> 0;
    v[h % DIM] += 1;
  }
  const n = Math.hypot(...v) || 1;
  return v.map((x) => x / n);
}
const cosDist = (a, b) => 1 - a.reduce((s, x, i) => s + x * b[i], 0);

function get(obj, path) {
  return path.split('.').reduce((o, k) => (o == null ? o : o[k]), obj);
}
function applyQueries(items, queries, vecField) {
  let out = [...items];
  let limit = 25;
  let vector = null;
  for (const raw of queries) {
    const q = JSON.parse(raw);
    if (q.method === 'equal') out = out.filter((d) => q.values.map(String).includes(String(get(d, q.attribute))));
    else if (q.method === 'between') out = out.filter((d) => get(d, q.attribute) >= q.values[0] && get(d, q.attribute) <= q.values[1]);
    else if (q.method === 'limit') limit = q.values[0];
    else if (q.method === 'vectorCosine') vector = q.values[0];
  }
  if (vector) out = out.map((d) => ({ ...d, $distance: cosDist(d[vecField], vector) })).sort((a, b) => a.$distance - b.$distance);
  return out.slice(0, limit);
}

function fakes() {
  const rows = [];
  const vdocs = { tx_vectors: [], category_seeds: [] };
  for (const [category, text] of SEED_EXAMPLES) {
    vdocs.category_seeds.push({ $id: `g${text}`, embeddings: fakeEmbed(text), metadata: { userId: 'global', category, text } });
  }
  const notFound = () => Object.assign(new Error('not found'), { code: 404 });
  const findRow = (id) => rows.find((r) => r.$id === id);
  return {
    rows,
    vdocs,
    embeddings: {
      createTextEmbeddings: async ({ texts }) => ({ embeddings: texts.map((t) => ({ embedding: fakeEmbed(t), error: '' })) }),
    },
    tablesDB: {
      createRow: async ({ rowId, data }) => {
        if (rows.some((r) => r.$id === rowId)) throw Object.assign(new Error('exists'), { code: 409 });
        const row = { $id: rowId, ...data };
        rows.push(row);
        return row;
      },
      listRows: async ({ queries }) => ({ rows: applyQueries(rows, queries.filter((q) => !q.includes('cursorAfter'))) }),
      getRow: async ({ rowId }) => findRow(rowId) ?? Promise.reject(notFound()),
      updateRow: async ({ rowId, data }) => Object.assign(findRow(rowId), data),
      deleteRow: async ({ rowId }) => { rows.splice(rows.indexOf(findRow(rowId)), 1); },
    },
    vectorsDB: {
      upsertDocument: async ({ collectionId, documentId, data }) => {
        const list = vdocs[collectionId];
        const i = list.findIndex((d) => d.$id === documentId);
        if (i >= 0) list.splice(i, 1);
        list.push({ $id: documentId, ...data });
      },
      deleteDocument: async ({ collectionId, documentId }) => {
        const list = vdocs[collectionId];
        const i = list.findIndex((d) => d.$id === documentId);
        if (i < 0) throw notFound();
        list.splice(i, 1);
      },
      createDocument: async ({ collectionId, documentId, data }) => {
        vdocs[collectionId].push({ $id: documentId, ...data });
      },
      listDocuments: async ({ collectionId, queries }) => ({ documents: applyQueries(vdocs[collectionId], queries, 'embeddings') }),
      createQuery: async ({ collectionId, queries }) => ({ documents: applyQueries(vdocs[collectionId], queries, 'embeddings') }),
    },
  };
}

const NOW = new Date('2026-10-26T12:00:00Z');

test('ingest + ask end to end', async () => {
  const svc = fakes();
  const alerts = fixtures.map((f) => ({ text: f.raw, sender: f.sender, receivedAt: '2026-10-26T12:00:00Z' }));
  const { results } = await ingest(svc, 'u1', { alerts }, console.log);

  assert.equal(results.filter((r) => r.status === 'created').length, 7);
  assert.equal(results.filter((r) => r.status === 'unparsed').length, 1);
  assert.equal(svc.rows.length, 7);

  // Duplicate paste is ignored
  const again = await ingest(svc, 'u1', { text: fixtures[0].raw }, console.log);
  assert.equal(again.results[0].status, 'duplicate');

  const fuel = await ask(svc, 'u1', 'How much did I spend on fuel in September?', NOW);
  assert.equal(fuel.totalKobo, 1500000, fuel.answer);
  assert.match(fuel.answer, /₦15,000\.00/);

  const emeka = await ask(svc, 'u1', 'show transfers to Emeka', NOW);
  const amounts = emeka.items.map((i) => i.amountKobo).sort();
  assert.deepEqual(amounts, [250000, 500000], JSON.stringify(emeka.items.map((i) => [i.description, i.distance])));

  const income = await ask(svc, 'u1', 'how much did I receive this month', NOW);
  assert.equal(income.totalKobo, 12000000 + 25000000, income.answer);

  // Another user's data never leaks
  const other = await ask(svc, 'u2', 'how much did I spend in September', NOW);
  assert.equal(other.count, 0);
});

test('fixing a category teaches the app, and delete removes everywhere', async () => {
  const svc = fakes();
  const first = await ingest(svc, 'u1', { text: 'GTBank Alert\nAmt: NGN9,000.00 DR\nDesc: POS PURCHASE OBONG VENTURES UYO\nDate: 2026-10-10' }, console.log);
  const row = first.results[0].row;
  assert.equal(row.category, 'other');

  // Another alert from the same merchant before the fix
  await ingest(svc, 'u1', { text: 'GTBank Alert\nAmt: NGN4,000.00 DR\nDesc: POS PURCHASE OBONG VENTURES UYO\nDate: 2026-10-12' }, console.log);

  const fix = await recategorize(svc, 'u1', { rowId: row.$id, category: 'groceries' });
  assert.equal(fix.updated, 1);
  assert.equal(fix.similar, 1, 'offers to fix the other Obong Ventures row');
  assert.equal(svc.rows.find((r) => r.$id === row.$id).categorySource, 'user');

  const all = await recategorize(svc, 'u1', { rowId: row.$id, category: 'groceries', applyToSimilar: true });
  assert.equal(all.updated, 2);

  // A new branch of the same merchant now lands in groceries via the user's seed
  const next = await ingest(svc, 'u1', { text: 'GTBank Alert\nAmt: NGN2,000.00 DR\nDesc: POS PURCHASE OBONG VENTURES EWET\nDate: 2026-10-20' }, console.log);
  assert.equal(next.results[0].row.category, 'groceries');
assert.equal(next.results[0].row.categorySource, 'user');  // Another user does not inherit u1's correction
  const other = await ingest(svc, 'u2', { text: 'GTBank Alert\nAmt: NGN2,000.00 DR\nDesc: POS PURCHASE OBONG VENTURES EWET\nDate: 2026-10-20' }, console.log);
  assert.equal(other.results[0].row.category, 'other');

  // u2 cannot touch u1's row
  await assert.rejects(() => deleteTx(svc, 'u2', { rowId: row.$id }), /not found/);

  await deleteTx(svc, 'u1', { rowId: row.$id });
  assert.equal(svc.rows.some((r) => r.$id === row.$id), false);

  await assert.rejects(() => recategorize(svc, 'u1', { rowId: 'x', category: 'nope' }), /Unknown category/);
});
