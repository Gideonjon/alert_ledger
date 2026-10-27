import * as sdk from 'node-appwrite';
import { IDS, MAX_CATEGORY_DISTANCE, MAX_SEARCH_DISTANCE } from './config.js';

const { Query } = sdk;

/** Embed many strings in one call. Returns number[][] in input order. */
export async function embed(embeddings, texts) {
  if (!texts.length) return [];
  const res = await embeddings.createTextEmbeddings({ texts });
  return res.embeddings.map((e) => {
    if (e.error) throw new Error(`embedding failed: ${e.error}`);
    return e.embedding;
  });
}

/** The text we embed for a transaction: what a person would search for. */
export function embedTextFor(tx) {
  return [
    tx.direction === 'credit' ? 'money received' : 'money spent',
    tx.description,
    tx.counterparty && `${tx.direction === 'credit' ? 'from' : 'to'} ${tx.counterparty}`,
    tx.category && tx.category !== 'other' && tx.category.replace('_', ' '),
  ].filter(Boolean).join(' · ');
}

/**
 * Nearest-neighbour category vote against the labelled seeds collection.
 * Returns { category, distance } or null when nothing is close enough.
 */
export async function categorizeByVector(vectorsDB, vector, userId) {
  const res = await vectorsDB.createQuery({
    databaseId: IDS.vectorsDb,
    collectionId: IDS.categorySeeds,
    queries: [
      Query.vectorCosine('embeddings', vector),
      // Built-in examples plus the ones this user taught by fixing a category
      Query.equal('metadata.userId', ['global', userId]),
      Query.limit(5),
      Query.select(['metadata']),
    ],
  });
  const close = res.documents.filter((d) => d.$distance <= MAX_CATEGORY_DISTANCE);
  if (!close.length) return null;

  // Distance-weighted vote so one very close seed beats two vague ones.
  // The user's own corrections count double: they know their merchants.
  const score = {};
  for (const d of close) {
    const c = d.metadata.category;
    const weight = d.metadata.userId === userId ? 2 : 1;
    score[c] = (score[c] || 0) + weight * (1 - d.$distance);
  }
  const [category] = Object.entries(score).sort((a, b) => b[1] - a[1])[0];
  return { category, distance: close[0].$distance };
}

export async function storeTxVector(vectorsDB, { rowId, userId, tx, vector, text }) {
  return vectorsDB.createDocument({
    databaseId: IDS.vectorsDb,
    collectionId: IDS.txVectors,
    documentId: rowId, // same id as the TablesDB row, so joining is trivial
    data: {
      embeddings: vector,
      metadata: {
        userId,
        rowId,
        date: tx.date, // 'YYYY-MM-DD' — metadata compares as strings, which sorts correctly
        direction: tx.direction,
        category: tx.category,
        text,
      },
    },
    permissions: [sdk.Permission.read(sdk.Role.user(userId))],
  });
}

/** Remember a user's correction as a personal labelled example. */
export async function storeUserSeed(vectorsDB, { userId, rowId, category, text, vector }) {
  return vectorsDB.upsertDocument({
    databaseId: IDS.vectorsDb,
    collectionId: IDS.categorySeeds,
    documentId: `s${rowId}`, // one seed per transaction, so re-correcting overwrites it
    data: { embeddings: vector, metadata: { userId, rowId, category, text } },
    permissions: [sdk.Permission.read(sdk.Role.user(userId))],
  });
}

/** Semantic search over one user's transactions, optionally scoped by date and direction. */
export async function searchTx(vectorsDB, { userId, vector, from, to, direction, limit = 50 }) {
  const queries = [
    Query.vectorCosine('embeddings', vector),
    Query.equal('metadata.userId', [userId]),
    Query.select(['metadata']),
    Query.limit(limit),
  ];
  if (from && to) queries.push(Query.between('metadata.date', from, to));
  if (direction) queries.push(Query.equal('metadata.direction', [direction]));

  // createQuery sends queries in the body, so the 768-dim vector never bloats the URL
  const res = await vectorsDB.createQuery({
    databaseId: IDS.vectorsDb,
    collectionId: IDS.txVectors,
    queries,
  });
  return res.documents
    .filter((d) => d.$distance <= MAX_SEARCH_DISTANCE)
    .map((d) => ({ rowId: d.metadata.rowId, distance: d.$distance }));
}
