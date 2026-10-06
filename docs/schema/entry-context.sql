-- Portable entry fields previously absent from the Reminder gateway payload.
BEGIN;
ALTER TABLE savy.reminders
  ADD COLUMN IF NOT EXISTS when_i_am TEXT,
  ADD COLUMN IF NOT EXISTS marks_clear_sign_of_success BOOLEAN,
  ADD COLUMN IF NOT EXISTS marks_compounding BOOLEAN;
COMMIT;
