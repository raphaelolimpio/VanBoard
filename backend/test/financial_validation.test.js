const assert = require('node:assert/strict');
const test = require('node:test');
const {
  transactionDateFilter,
  isValidFinancialReceipt
} = require('../src/financial_validation');

test('accepts a full date range and makes the ending day inclusive', () => {
  const result = transactionDateFilter({ from: '2026-10-01', to: '2026-10-31' });

  assert.equal(result.error, null);
  assert.equal(result.date.gte.toISOString(), '2026-10-01T00:00:00.000Z');
  assert.equal(result.date.lt.toISOString(), '2026-11-01T00:00:00.000Z');
});

test('rejects invalid and reversed transaction date ranges', () => {
  assert.equal(
    transactionDateFilter({ from: 'not-a-date' }).error,
    'Data inicial inválida.'
  );
  assert.equal(
    transactionDateFilter({ from: '2026-10-31', to: '2026-10-01' }).error,
    'O período informado é inválido.'
  );
});

test('accepts only size-limited JPEG and PNG receipt bytes matching their MIME type', () => {
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0x00]);
  const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0x00]);

  assert.equal(isValidFinancialReceipt('image/jpeg', jpeg), true);
  assert.equal(isValidFinancialReceipt('image/png', png), true);
  assert.equal(isValidFinancialReceipt('image/png', jpeg), false);
  assert.equal(isValidFinancialReceipt('application/pdf', png), false);
  assert.equal(isValidFinancialReceipt('image/png', Buffer.alloc(5 * 1024 * 1024 + 1)), false);
});
