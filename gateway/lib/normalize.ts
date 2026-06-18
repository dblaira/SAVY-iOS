type JsonRecord = Record<string, unknown>;

export function normalizeCorrelation(raw: unknown): JsonRecord {
  const row = (raw ?? {}) as JsonRecord;
  return {
    category_a: row.category_a ?? row.categoryA,
    category_b: row.category_b ?? row.categoryB,
    coefficient: row.coefficient,
    lag: row.lag,
    type: row.type,
  };
}

export function normalizeCategoryStat(raw: unknown): JsonRecord {
  const row = (raw ?? {}) as JsonRecord;
  return {
    category: row.category,
    mean: row.mean,
    std_dev: row.std_dev ?? row.stdDev,
    weeks_with_data: row.weeks_with_data ?? row.weeksWithData,
    total_count: row.total_count ?? row.totalCount,
    coverage_percent: row.coverage_percent ?? row.coveragePercent,
  };
}

export function normalizeCorrelations(rows: unknown): unknown[] {
  if (!Array.isArray(rows)) return [];
  return rows.map(normalizeCorrelation);
}

export function normalizeCategoryStats(rows: unknown): unknown[] {
  if (!Array.isArray(rows)) return [];
  return rows.map(normalizeCategoryStat);
}
