/** Agregação das latências. Sem dependência de plataforma — testável em qualquer lugar. */

export function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  // Interpolação linear entre as posições vizinhas.
  const idx = (sorted.length - 1) * p;
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  return lo === hi ? sorted[lo] : sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
}

export function summarize(values: number[]) {
  return {
    median: percentile(values, 0.5),
    p95: percentile(values, 0.95),
    min: values.length ? Math.min(...values) : 0,
  };
}

export const ms = (n: number) => `${n.toFixed(1)} ms`;
