/**
 * dd/mm/aaaa hh:mm, montado à mão: o `toLocaleString` depende do suporte a
 * Intl do motor JavaScript, e errar a data de uma captura é pior que formatar
 * sem biblioteca.
 */
export function formatDate(ms: number): string {
  const d = new Date(ms);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

/** Megabytes com uma casa: o que importa é a ordem de grandeza. */
export function formatMegabytes(bytes: number): string {
  return `${(bytes / 1_000_000).toFixed(1)} MB`;
}

/** mm:ss, ou h:mm:ss passada uma hora. */
export function formatElapsed(ms: number): string {
  const total = Math.floor(ms / 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return h > 0 ? `${h}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
}
