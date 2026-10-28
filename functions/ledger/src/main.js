
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
    .setKey(
      req.headers['x-appwrite-key'] ||
      process.env.APPWRITE_API_KEY,
    );

  return { tablesDB: new sdk.TablesDB(client) };
}

function rowIdFor(userId, raw) {
  const normalized = String(raw)
    .replace(/\s+/g, ' ')
    .trim()
    .toUpperCase();

  return crypto
    .createHash('sha256')
    .update(`${userId}|${normalized}`)
    .digest('hex')
    .slice(0, 32);
}

function merchantRuleId(userId, key) {
  return crypto
    .createHash('sha256')
    .update(`${userId}|${key}`)
    .digest('hex')
    .slice(0, 32);
}

const naira = (kobo) =>
  `₦${(Number(kobo || 0) / 100).toLocaleString('en-NG', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;

function normalize(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Normalize a merchant name so transactions from different branches
 * can share a learned category.
 *
 * Examples:
 * "POS PURCHASE OBONG VENTURES UYO"  -> "obong ventures"
 * "POS PURCHASE OBONG VENTURES EWET" -> "obong ventures"
 */
function merchantKey(description, counterparty = '') {
  let value = normalize(counterparty || description);

  // Remove common transaction descriptions that are not merchant names.
  value = value.replace(
    /^(?:(?:pos|web|online|card|atm)\s+)*(?:purchase|payment|transaction|transfer|withdrawal|deposit)\s+/,
    '',
  );

  // Remove leading payment-channel terms if they remain.
  value = value.replace(
    /^(?:pos|web|online|card|atm|purchase|payment|transfer)\s+/,
    '',
  );

  // Remove common location suffixes that can vary between branches.
  value = value.replace(
    /\s+(?:uyo|ewet|uyo town|akwa ibom|lagos|abuja|calabar|port harcourt)$/,
    '',
  );

  return value.replace(/\s+/g, ' ').trim().slice(0, 120);
}

function getMerchantRuleTableId() {
  if (!IDS.merchantRulesTable) {
    throw new Error(
      'LEDGER_MERCHANT_RULES_TABLE_ID is not configured.',
    );
  }

  return IDS.merchantRulesTable;
}

/**
 * Paginate through a TablesDB table.
 * Only use this helper with a user-scoped query when reading user data.
 */
async function listRowsAll(
  tablesDB,
  queries = [],
  max = 1000,
  tableId = IDS.transactionsTable,
) {
  const rows = [];
  let cursor = null;

  while (rows.length < max) {
    const limit = Math.min(100, max - rows.length);

    const page = await tablesDB.listRows({
      databaseId: IDS.tablesDb,
      tableId,
      queries: [
        ...queries,
        Query.limit(limit),
        ...(cursor ? [Query.cursorAfter(cursor)] : []),
      ],
    });

    rows.push(...page.rows);

    if (page.rows.length < limit || page.rows.length === 0) {
      break;
    }

    cursor = page.rows.at(-1).$id;
  }

  return rows.slice(0, max);
}

/**
 * Look up the current user's saved category for a merchant.
 * A merchant rule is never shared across users.
 */
async function findMerchantRule(
  tablesDB,
  userId,
  description,
  counterparty = '',
) {
  const key = merchantKey(description, counterparty);

  if (!key) return null;

  const rules = await listRowsAll(
    tablesDB,
    [Query.equal('userId', [userId])],
    1000,
    getMerchantRuleTableId(),
  );

  // Prefer an exact merchant match.
  const exact = rules.find(
    (rule) => normalize(rule.merchantKey) === key,
  );

  if (exact) return exact;

  // Permit a close match when a branch/location suffix differs.
  // Require at least two words to avoid matching overly broad names.
  const words = key.split(' ').filter(Boolean);

  if (words.length < 2) return null;

  const matches = rules.filter((rule) => {
    const savedKey = normalize(rule.merchantKey);

    return (
      savedKey.length >= 5 &&
      (key.startsWith(`${savedKey} `) ||
        savedKey.startsWith(`${key} `))
    );
  });

  matches.sort(
    (a, b) =>
      normalize(b.merchantKey).length -
      normalize(a.merchantKey).length,
  );

  return matches[0] || null;
}

/**
 * Save or update a merchant rule for one user.
 */
async function saveMerchantRule(
  tablesDB,
  userId,
  description,
  category,
  counterparty = '',
) {
  const key = merchantKey(description, counterparty);

  if (!key) return null;

  const tableId = getMerchantRuleTableId();
  const rowId = merchantRuleId(userId, key);

  const data = {
    userId,
    merchantKey: key,
    category,
  };

  try {
    return await tablesDB.createRow({
      databaseId: IDS.tablesDb,
      tableId,
      rowId,
      data,
    });
  } catch (e) {
    if (e.code !== 409) throw e;

    // A rule with this deterministic ID already exists.
    return await tablesDB.updateRow({
      databaseId: IDS.tablesDb,
      tableId,
      rowId,
      data: { category },
    });
  }
}

export async function ingest(
  { tablesDB },
  userId,
  body,
  log = () => {},
) {
  const alerts = Array.isArray(body.alerts)
    ? body.alerts
    : [body];

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

    const description = String(tx.description || inputText);
    const counterparty = String(tx.counterparty || '');

    let category;
    let categorySource;

    try {
      // Manual merchant rules take priority over automatic categorization.
      const learnedRule = await findMerchantRule(
        tablesDB,
        userId,
        description,
        counterparty,
      );

      if (learnedRule) {
        category = learnedRule.category;
        categorySource = 'user';
      } else {
        const keywordCategory = categorizeByKeyword(description);

        category = keywordCategory || 'other';
        categorySource = keywordCategory ? 'keyword' : 'none';
      }
    } catch (e) {
      // Do not silently hide a database/configuration problem.
      log(`merchant rule lookup error: ${e.message}`);

      const keywordCategory = categorizeByKeyword(description);
      category = keywordCategory || 'other';
      categorySource = keywordCategory ? 'keyword' : 'none';
    }

    // A credit described as a transfer is treated as income,
    // unless the user has explicitly corrected its category.
    if (
      tx.direction === 'credit' &&
      category === 'transfer' &&
      categorySource !== 'user'
    ) {
      category = 'income';
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
          description: description.slice(0, 500),
          counterparty: counterparty.slice(0, 120),
          category,
          categorySource,
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
        results.push({
          status: 'error',
          message: e.message,
        });
      }
    }
  }

  return { results };
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

  // Every search term must appear somewhere in the transaction.
  return terms.every((term) => searchable.includes(term));
}

export async function ask(
  { tablesDB },
  userId,
  question,
  now = new Date(),
) {
  const q = parseQuestion(question, now);

  const scope = [
    Query.equal('userId', [userId]),
  ];

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

  // Read only this user's transactions.
  let rows = await listRowsAll(tablesDB, scope);

  if (q.category) {
    rows = rows.filter((row) => row.category === q.category);
  }

  if (q.topic) {
    rows = rows.filter((row) => matchesTopic(row, q.topic));
  }

  rows.sort(
    (a, b) => String(b.txDate).localeCompare(String(a.txDate)),
  );

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
    answer =
      `${rows.length} transaction${rows.length === 1 ? '' : 's'}` +
      `${about}${span}.`;
  } else {
    answer =
      `You ${verb} ${naira(totalKobo)}${about}${span} across ` +
      `${rows.length} transaction${rows.length === 1 ? '' : 's'}.`;
  }

  return {
    answer,
    totalKobo,
    count: rows.length,
    parsed: q,
    items: rows.map((row) => ({
      ...row,
      matchedBy: q.category
        ? 'category'
        : q.topic
          ? 'text'
          : 'range',
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
  if (!rowId) {
    throw new HttpError(400, 'rowId is required');
  }

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

  // Avoid revealing that another user's transaction exists.
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

  // Persist the correction so future transactions from this merchant
  // receive the same category.
  await saveMerchantRule(
    tablesDB,
    userId,
    row.description,
    category,
    row.counterparty,
  );

  const targets = [row];

  if (applyToSimilar && row.counterparty) {
    const same = await listRowsAll(tablesDB, [
      Query.equal('userId', [userId]),
      Query.equal('counterparty', [row.counterparty]),
    ]);

    targets.push(
      ...same.filter(
        (item) =>
          item.$id !== row.$id &&
          item.category !== category,
      ),
    );
  }

  for (const item of targets) {
    await tablesDB.updateRow({
      databaseId: IDS.tablesDb,
      tableId: IDS.transactionsTable,
      rowId: item.$id,
      data: {
        category,
        categorySource: 'user',
      },
    });
  }

  let similar = 0;

  if (!applyToSimilar && row.counterparty) {
    const same = await listRowsAll(tablesDB, [
      Query.equal('userId', [userId]),
      Query.equal('counterparty', [row.counterparty]),
    ]);

    similar = same.filter(
      (item) =>
        item.$id !== row.$id &&
        item.category !== category,
    ).length;
  }

  return {
    updated: targets.length,
    similar,
    learned: true,
    category,
  };
}

export async function deleteTx(
  { tablesDB },
  userId,
  { rowId },
) {
  await ownedRow(tablesDB, userId, rowId);

  await tablesDB.deleteRow({
    databaseId: IDS.tablesDb,
    tableId: IDS.transactionsTable,
    rowId,
  });

  // Keep the merchant rule. Deleting one transaction should not erase
  // the user's learned preference for that merchant.
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
        return res.json(
          { error: 'question is required' },
          400,
        );
      }

      return res.json(
        await ask(svc, userId, body.question),
      );
    }

    if (req.method === 'POST' && req.path === '/recategorize') {
      return res.json(
        await recategorize(svc, userId, body),
      );
    }

    if (req.method === 'POST' && req.path === '/delete') {
      return res.json(
        await deleteTx(svc, userId, body),
      );
    }

    return res.json({ error: 'Not found' }, 404);
  } catch (e) {
    if (e instanceof HttpError) {
      return res.json({ error: e.message }, e.status);
    }

    error(e.stack || e.message);

    return res.json(
      { error: e.message || 'Internal server error' },
      500,
    );
  }
};
