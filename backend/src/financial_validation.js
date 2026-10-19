function transactionDateFilter(query) {
  if (!query.from && !query.to) return { date: null, error: null };
  const date = {};
  if (query.from) {
    if (typeof query.from !== 'string') {
      return { date: null, error: 'Data inicial inválida.' };
    }
    date.gte = new Date(query.from);
    if (Number.isNaN(date.gte.getTime())) {
      return { date: null, error: 'Data inicial inválida.' };
    }
  }
  if (query.to) {
    if (typeof query.to !== 'string') {
      return { date: null, error: 'Data final inválida.' };
    }
    const to = new Date(query.to);
    if (Number.isNaN(to.getTime())) {
      return { date: null, error: 'Data final inválida.' };
    }
    to.setUTCDate(to.getUTCDate() + 1);
    date.lt = to;
  }
  if (date.gte && date.lt && date.gte >= date.lt) {
    return { date: null, error: 'O período informado é inválido.' };
  }
  return { date, error: null };
}

function isValidFinancialReceipt(mimeType, data) {
  if (!Buffer.isBuffer(data) || data.length === 0 || data.length > 5 * 1024 * 1024) {
    return false;
  }
  if (mimeType === 'image/jpeg') {
    return data.length >= 3 && data[0] === 0xff &&
      data[1] === 0xd8 && data[2] === 0xff;
  }
  if (mimeType === 'image/png') {
    return data.length >= 8 &&
      data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  }
  return false;
}

module.exports = { transactionDateFilter, isValidFinancialReceipt };
