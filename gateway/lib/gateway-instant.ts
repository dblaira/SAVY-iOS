/** Aurora `timestamptz::text` is `2026-10-05 20:16:48.331407+00`, which the iOS date parser rejects. */
export function gatewayInstant(value: unknown): string | null {
  if (value == null || value === "") return null;
  const date = value instanceof Date ? value : new Date(String(value));
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}
