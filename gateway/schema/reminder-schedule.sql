-- Apply before deploying the Schedule-aware gateway. Existing rows keep an unknown
-- (NULL) version so their first new client can upload a device-local Schedule.
BEGIN;
ALTER TABLE savy.reminders
  ADD COLUMN IF NOT EXISTS schedule JSONB,
  ADD COLUMN IF NOT EXISTS schedule_version SMALLINT;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
    WHERE conrelid = 'savy.reminders'::regclass AND conname = 'reminders_schedule_check') THEN
    ALTER TABLE savy.reminders ADD CONSTRAINT reminders_schedule_check CHECK (
      (schedule_version IS NULL OR schedule_version = 1)
      AND (schedule IS NULL OR (schedule_version IS NOT NULL
        AND schedule_version = 1 AND jsonb_typeof(schedule) = 'object'))
    );
  END IF;
END $$;
COMMIT;
