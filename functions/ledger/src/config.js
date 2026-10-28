
export const IDS = {
  tablesDb: process.env.LEDGER_TABLES_DB_ID || 'ledger',
  transactionsTable:
    process.env.LEDGER_TX_TABLE_ID || 'transactions',
  merchantRulesTable:
    process.env.LEDGER_MERCHANT_RULES_TABLE_ID || 'merchant_rules',
};
