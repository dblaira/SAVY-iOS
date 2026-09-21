-- Add optional stable Post numbering to normal reminder records.
-- Existing rows stay unnumbered until their normal native sync; no content,
-- timestamps, deleted rows, or RDF authority data are changed by this migration.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE savy.reminders ADD COLUMN IF NOT EXISTS post_number INTEGER;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'savy.reminders'::regclass
      AND conname = 'reminders_post_number_positive'
  ) THEN
    ALTER TABLE savy.reminders ADD CONSTRAINT reminders_post_number_positive
      CHECK (post_number > 0);
  END IF;
END $$;
COMMIT;
