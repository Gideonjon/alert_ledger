// IDs shared by the function, the setup script and the Flutter app.
export const IDS = {
  tablesDb: process.env.LEDGER_TABLES_DB_ID || 'ledger',
  transactionsTable: process.env.LEDGER_TX_TABLE_ID || 'transactions',
  vectorsDb: process.env.LEDGER_VECTORS_DB_ID || 'ledger_vectors',
  txVectors: process.env.LEDGER_TX_VECTORS_ID || 'tx_vectors',
  categorySeeds: process.env.LEDGER_SEEDS_ID || 'category_seeds',
};

// nomic-embed-text is Appwrite's default model and produces 768-dim vectors.
export const EMBED_DIMENSION = 768;

// Cosine distance cut-offs (0 = identical). Tune these against your own data on day 3.
export const MAX_SEARCH_DISTANCE = Number(process.env.LEDGER_MAX_SEARCH_DISTANCE || 0.5);
export const MAX_CATEGORY_DISTANCE = Number(process.env.LEDGER_MAX_CATEGORY_DISTANCE || 0.55);
