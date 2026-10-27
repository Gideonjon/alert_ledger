// Provision Alert Ledger using TablesDB only.
// Required environment variables:
// APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY

import * as sdk from 'node-appwrite';
import { IDS } from '../src/config.js';

const ENDPOINT = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;

if (!ENDPOINT || !PROJECT || !KEY) {
  console.error(
    'Set APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID and APPWRITE_API_KEY',
  );
  process.exit(1);
}

const client = new sdk.Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT)
  .setKey(KEY);

const tablesDB = new sdk.TablesDB(client);

async function step(label, fn) {
  try {
    await fn();
    console.log(`✓ ${label}`);
  } catch (e) {
    if (e.code === 409) {
      console.log(`• ${label} (already exists)`);
      return;
    }

    throw new Error(`${label}: ${e.message}`);
  }
}

const db = IDS.tablesDb;
const table = IDS.transactionsTable;

await step('TablesDB database', () =>
  tablesDB.create({
    databaseId: db,
    name: 'Alert Ledger',
  }),
);

await step('Transactions table', () =>
  tablesDB.createTable({
    databaseId: db,
    tableId: table,
    name: 'Transactions',
    permissions: [],
    rowSecurity: true,
  }),
);

const columns = [
  ['userId', () => tablesDB.createVarcharColumn({
    databaseId: db, tableId: table, key: 'userId',
    size: 36, required: true,
  })],
  ['direction', () => tablesDB.createEnumColumn({
    databaseId: db, tableId: table, key: 'direction',
    elements: ['debit', 'credit'], required: true,
  })],
  ['amountKobo', () => tablesDB.createBigIntColumn({
    databaseId: db, tableId: table, key: 'amountKobo',
    required: true, min: 0,
  })],
  ['balanceKobo', () => tablesDB.createBigIntColumn({
    databaseId: db, tableId: table, key: 'balanceKobo',
    required: false,
  })],
  ['description', () => tablesDB.createVarcharColumn({
    databaseId: db, tableId: table, key: 'description',
    size: 500, required: false, xdefault: '',
  })],
  ['counterparty', () => tablesDB.createVarcharColumn({
    databaseId: db, tableId: table, key: 'counterparty',
    size: 120, required: false, xdefault: '',
  })],
  ['category', () => tablesDB.createVarcharColumn({
    databaseId: db, tableId: table, key: 'category',
    size: 32, required: true,
  })],
  ['categorySource', () => tablesDB.createVarcharColumn({
    databaseId: db, tableId: table, key: 'categorySource',
    size: 16, required: false, xdefault: 'keyword',
  })],
  ['bank', () => tablesDB.createVarcharColumn({
    databaseId: db, tableId: table, key: 'bank',
    size: 32, required: false, xdefault: 'unknown',
  })],
  ['txDate', () => tablesDB.createDatetimeColumn({
    databaseId: db, tableId: table, key: 'txDate',
    required: true,
  })],
  ['raw', () => tablesDB.createTextColumn({
    databaseId: db, tableId: table, key: 'raw',
    required: false,
  })],
];

for (const [name, create] of columns) {
  await step(`Column ${name}`, create);
}

console.log('Waiting for columns to become available...');
await new Promise((resolve) => setTimeout(resolve, 4000));

const indexes = [
  ['idx_user_date', ['userId', 'txDate']],
  ['idx_user_dir_date', ['userId', 'direction', 'txDate']],
  ['idx_user_cat_date', ['userId', 'category', 'txDate']],
];

for (const [key, columns] of indexes) {
  await step(`Index ${key}`, () =>
    tablesDB.createIndex({
      databaseId: db,
      tableId: table,
      key,
      type: sdk.TablesDBIndexType.Key,
      columns,
    }),
  );
}

console.log('\nTablesDB setup complete. No VectorsDB is required.');
