// One-off provisioning for Alert Ledger. Safe to re-run: existing resources are skipped.
//
//   APPWRITE_ENDPOINT=https://<REGION>.cloud.appwrite.io/v1 \
//   APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... npm run setup
//
// The API key needs: databases, tables, columns, indexes, rows, collections,
// documents (read+write) and embeddings.write.
import * as sdk from 'node-appwrite';
import { IDS, EMBED_DIMENSION } from '../src/config.js';
import { SEED_EXAMPLES } from '../src/categories.js';

const ENDPOINT = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;
if (!ENDPOINT || !PROJECT || !KEY) {
  console.error('Set APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID and APPWRITE_API_KEY');
  process.exit(1);
}

const client = new sdk.Client().setEndpoint(ENDPOINT).setProject(PROJECT).setKey(KEY);
const tablesDB = new sdk.TablesDB(client);
const vectorsDB = new sdk.VectorsDB(client);
const embeddings = new sdk.Embeddings(client);
const { Permission, Role } = sdk;

async function step(label, fn) {
  try {
    await fn();
    console.log(`✓ ${label}`);
  } catch (e) {
    if (e.code === 409) console.log(`• ${label} (already exists)`);
    else throw new Error(`${label}: ${e.message}`);
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- TablesDB: the ledger of record ----------
const db = IDS.tablesDb;
const t = IDS.transactionsTable;

await step('TablesDB database', () => tablesDB.create({ databaseId: db, name: 'Alert Ledger' }));
await step('transactions table', () => tablesDB.createTable({
  databaseId: db,
  tableId: t,
  name: 'Transactions',
  permissions: [], // rows carry their own per-user permissions
  rowSecurity: true,
}));

const cols = [
  ['userId', () => tablesDB.createVarcharColumn({ databaseId: db, tableId: t, key: 'userId', size: 36, required: true })],
  ['direction', () => tablesDB.createEnumColumn({ databaseId: db, tableId: t, key: 'direction', elements: ['debit', 'credit'], required: true })],
  ['amountKobo', () => tablesDB.createBigIntColumn({ databaseId: db, tableId: t, key: 'amountKobo', required: true, min: 0 })],
  ['balanceKobo', () => tablesDB.createBigIntColumn({ databaseId: db, tableId: t, key: 'balanceKobo', required: false })],
  ['description', () => tablesDB.createVarcharColumn({ databaseId: db, tableId: t, key: 'description', size: 500, required: false, xdefault: '' })],
  ['counterparty', () => tablesDB.createVarcharColumn({ databaseId: db, tableId: t, key: 'counterparty', size: 120, required: false, xdefault: '' })],
  ['category', () => tablesDB.createVarcharColumn({ databaseId: db, tableId: t, key: 'category', size: 32, required: true })],
  ['categorySource', () => tablesDB.createVarcharColumn({ databaseId: db, tableId: t, key: 'categorySource', size: 16, required: false, xdefault: 'keyword' })],
  ['bank', () => tablesDB.createVarcharColumn({ databaseId: db, tableId: t, key: 'bank', size: 32, required: false, xdefault: 'unknown' })],
  ['txDate', () => tablesDB.createDatetimeColumn({ databaseId: db, tableId: t, key: 'txDate', required: true })],
  ['raw', () => tablesDB.createTextColumn({ databaseId: db, tableId: t, key: 'raw', required: false })],
];
for (const [name, fn] of cols) await step(`column ${name}`, fn);

console.log('…waiting for columns to become available');
await sleep(4000);

const idx = [
  ['idx_user_date', ['userId', 'txDate']],
  ['idx_user_dir_date', ['userId', 'direction', 'txDate']],
  ['idx_user_cat_date', ['userId', 'category', 'txDate']],
];
for (const [key, columns] of idx) {
  await step(`index ${key}`, () => tablesDB.createIndex({ databaseId: db, tableId: t, key, type: sdk.TablesDBIndexType.Key, columns }));
}

// ---------- VectorsDB: meaning ----------
const vdb = IDS.vectorsDb;
await step('VectorsDB database', () => vectorsDB.create({ databaseId: vdb, name: 'Alert Ledger Vectors' }));

for (const [id, name, documentSecurity] of [
  [IDS.txVectors, 'Transaction vectors', true],
  // Document security on: built-in seeds are readable by anyone, a user's own seeds only by them
  [IDS.categorySeeds, 'Category seeds', true],
]) {
  await step(`collection ${id}`, () => vectorsDB.createCollection({
    databaseId: vdb,
    collectionId: id,
    name,
    dimension: EMBED_DIMENSION,
    permissions: [],
    documentSecurity,
  }));
  await step(`HNSW cosine index on ${id}`, () => vectorsDB.createIndex({
    databaseId: vdb,
    collectionId: id,
    key: 'embeddings_index',
    type: sdk.VectorsDBIndexType.HnswCosine,
    attributes: ['embeddings'],
  }));
}

// ---------- Seed examples that teach the category layer ----------
const existing = await vectorsDB.listDocuments({ databaseId: vdb, collectionId: IDS.categorySeeds, queries: [sdk.Query.limit(1)] });
if (existing.total > 0) {
  console.log(`• category seeds (already ${existing.total})`);
} else {
  const res = await embeddings.createTextEmbeddings({ texts: SEED_EXAMPLES.map(([, text]) => text) });
  for (let i = 0; i < SEED_EXAMPLES.length; i++) {
    const [category, text] = SEED_EXAMPLES[i];
    await vectorsDB.createDocument({
      databaseId: vdb,
      collectionId: IDS.categorySeeds,
      documentId: sdk.ID.unique(),
      data: { embeddings: res.embeddings[i].embedding, metadata: { userId: 'global', category, text } },
      permissions: [Permission.read(Role.any())],
    });
  }
  console.log(`✓ category seeds (${SEED_EXAMPLES.length})`);
}

console.log('\nDone. Next: deploy the function (see README) and give it execute access for "users".');
