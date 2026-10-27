import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseAlert } from '../src/parser.js';
import { categorizeByKeyword } from '../src/categories.js';
import { parseQuestion } from '../src/question.js';
import { fixtures } from './fixtures.js';

for (const f of fixtures) {
  test(`parse: ${f.name}`, () => {
    const r = parseAlert(f.raw, { sender: f.sender, receivedAt: '2026-10-26T12:00:00Z' });
    if (f.expectFail) {
      assert.equal(r.ok, false);
      return;
    }
    assert.equal(r.ok, true, JSON.stringify(r));
    for (const [k, v] of Object.entries(f.expect)) assert.equal(r[k], v, `${k}: ${JSON.stringify(r)}`);
  });
}

test('keyword categories', () => {
  assert.equal(categorizeByKeyword('POS/WEB PURCHASE TOTAL ENERGIES UYO'), 'fuel');
  assert.equal(categorizeByKeyword('AIRTIME MTN 0803'), 'airtime_data');
  assert.equal(categorizeByKeyword('SMS ALERT CHARGES SEP'), 'bank_charges');
  assert.equal(categorizeByKeyword('PHED PREPAID TOKEN'), 'utilities');
  assert.equal(categorizeByKeyword('MAMA NKECHI KITCHEN'), 'food');
  // Unknown merchant: falls through to the vector layer
  assert.equal(categorizeByKeyword('POS OBONG VENTURES UYO'), null);
});

const NOW = new Date('2026-10-26T12:00:00Z');

test('question: spend on fuel in September', () => {
  const q = parseQuestion('How much did I spend on fuel in September?', NOW);
  assert.equal(q.intent, 'sum');
  assert.equal(q.direction, 'debit');
  assert.deepEqual([q.from, q.to], ['2026-09-01', '2026-09-30']);
  assert.equal(q.category, 'fuel');
  assert.equal(q.topic, 'fuel');
});

test('question: show transfers to Emeka', () => {
  const q = parseQuestion('show transfers to Emeka', NOW);
  assert.equal(q.intent, 'list');
  assert.equal(q.direction, 'debit');
  assert.equal(q.from, null);
  assert.match(q.topic, /emeka/);
});

test('question: income last month', () => {
  const q = parseQuestion('how much did I receive last month', NOW);
  assert.equal(q.direction, 'credit');
  assert.deepEqual([q.from, q.to], ['2026-09-01', '2026-09-30']);
});

test('question: last 7 days', () => {
  const q = parseQuestion('what did I spend in the last 7 days', NOW);
  assert.deepEqual([q.from, q.to], ['2026-10-20', '2026-10-26']);
});
