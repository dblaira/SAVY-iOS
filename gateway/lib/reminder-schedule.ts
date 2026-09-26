/** Portable Schedule data. EventKit calendar/event identifiers belong to one device. */
export type ReminderSchedule = {
  startDate: string;
  endDate: string;
  isAllDay: boolean;
  timeZoneIdentifier: string;
  alert: "none" | "atStart" | "fiveMinutesBefore" | "fifteenMinutesBefore"
    | "thirtyMinutesBefore" | "oneHourBefore" | "oneDayBefore" | "hourly";
  travelTimeMinutes: number;
  invitees?: string[];
  organizerEmail?: string;
};

export class ScheduleValidationError extends Error {}

const alerts = new Set([
  "none", "atStart", "fiveMinutesBefore", "fifteenMinutesBefore",
  "thirtyMinutesBefore", "oneHourBefore", "oneDayBefore", "hourly",
]);

function instant(value: unknown): number {
  if (typeof value !== "string"
    || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    throw new ScheduleValidationError("Schedule dates must be ISO8601 instants with a time zone.");
  }
  const result = Date.parse(value);
  // Date.parse can silently normalize impossible calendar dates, such as February 30.
  const [year, month, day] = value.slice(0, 10).split("-").map(Number);
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  if (!Number.isFinite(result) || date.getUTCFullYear() !== year
    || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    throw new ScheduleValidationError("Schedule dates must be valid instants.");
  }
  return result;
}

/** Missing fields mean an old client has no Schedule opinion; null explicitly clears it. */
export function normalizeScheduleFields(body: { schedule?: unknown; schedule_version?: unknown }): {
  schedule?: ReminderSchedule | null;
  schedule_version?: 1;
} {
  const hasSchedule = Object.prototype.hasOwnProperty.call(body, "schedule");
  if (!hasSchedule && body.schedule_version == null) return {};
  if (!hasSchedule || body.schedule_version !== 1) {
    throw new ScheduleValidationError("Schedule requires schedule_version 1 and a schedule object or null.");
  }
  if (body.schedule === null) return { schedule: null, schedule_version: 1 };
  if (typeof body.schedule !== "object" || Array.isArray(body.schedule)) {
    throw new ScheduleValidationError("Schedule must be an object or null.");
  }
  const value = body.schedule as Record<string, unknown>;
  const start = instant(value.startDate);
  const end = instant(value.endDate);
  if (end <= start) throw new ScheduleValidationError("Choose an end after the start.");
  if (typeof value.isAllDay !== "boolean") throw new ScheduleValidationError("Schedule isAllDay must be a boolean.");
  if (typeof value.timeZoneIdentifier !== "string" || !value.timeZoneIdentifier) {
    throw new ScheduleValidationError("Schedule requires a time zone.");
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value.timeZoneIdentifier }).format(0);
  } catch {
    throw new ScheduleValidationError("Schedule time zone is invalid.");
  }
  if (typeof value.alert !== "string" || !alerts.has(value.alert)) {
    throw new ScheduleValidationError("Schedule alert is invalid.");
  }
  if (!Number.isSafeInteger(value.travelTimeMinutes) || (value.travelTimeMinutes as number) < 0) {
    throw new ScheduleValidationError("Travel time must be a nonnegative whole number of minutes.");
  }
  if (value.alert === "hourly" && (value.isAllDay || end - start > 24 * 60 * 60 * 1000)) {
    throw new ScheduleValidationError("Hourly reminders require a timed period of 24 hours or less.");
  }
  if (value.invitees != null
    && (!Array.isArray(value.invitees) || !value.invitees.every((item) => typeof item === "string"))) {
    throw new ScheduleValidationError("Schedule invitees must be an array of strings.");
  }
  if (value.organizerEmail != null && typeof value.organizerEmail !== "string") {
    throw new ScheduleValidationError("Schedule organizerEmail must be a string.");
  }
  // Explicitly select portable fields, even if a client accidentally sends native identifiers.
  const schedule: ReminderSchedule = {
    startDate: value.startDate as string,
    endDate: value.endDate as string,
    isAllDay: value.isAllDay,
    timeZoneIdentifier: value.timeZoneIdentifier,
    alert: value.alert as ReminderSchedule["alert"],
    travelTimeMinutes: value.travelTimeMinutes as number,
  };
  if (value.invitees != null) schedule.invitees = value.invitees as string[];
  if (value.organizerEmail != null) schedule.organizerEmail = value.organizerEmail as string;
  return { schedule, schedule_version: 1 };
}
