// IDs shared by the function, setup script, and Flutter app.
export const IDS = {
  tablesDb: process.env.LEDGER_TABLES_DB_ID || 'ledger',
  transactionsTable: process.env.LEDGER_TX_TABLE_ID || 'transactions',
};
