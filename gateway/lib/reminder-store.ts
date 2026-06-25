import * as aurora from "./aurora-bridge.js";
import { gatewayPhase } from "./content-store.js";
import type { ReminderRow, ReminderUpsertInput } from "./aurora-bridge.js";

function usesAurora(): boolean {
  return gatewayPhase() !== "supabase-bridge";
}

export function reminderStoreAvailable(): boolean {
  return usesAurora();
}

export async function fetchUserReminders(userId: string): Promise<ReminderRow[]> {
  if (!usesAurora()) {
    return [];
  }
  return aurora.fetchRemindersForUser(userId);
}

export async function upsertUserReminder(
  userId: string,
  input: ReminderUpsertInput,
  email?: string | null
): Promise<void> {
  if (!usesAurora()) {
    throw new Error("Reminder sync requires Aurora");
  }
  await aurora.ensureSavyUser(userId, email);
  await aurora.upsertReminderForUser(userId, input);
}

export async function deleteUserReminder(userId: string, reminderId: string): Promise<void> {
  if (!usesAurora()) {
    throw new Error("Reminder sync requires Aurora");
  }
  await aurora.deleteReminderForUser(userId, reminderId);
}

export async function attachReminderImagePath(
  userId: string,
  reminderId: string,
  imagePath: string
): Promise<void> {
  if (!usesAurora()) {
    throw new Error("Reminder image sync requires Aurora");
  }
  await aurora.setReminderImagePath(userId, reminderId, imagePath);
}

export type { ReminderRow, ReminderUpsertInput };
