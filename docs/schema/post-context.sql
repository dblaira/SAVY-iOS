-- Preserve editable Post question-and-answer text in the normal reminder record.
-- No RDF tables or authority data are changed.
BEGIN;
ALTER TABLE savy.reminders
  ADD COLUMN IF NOT EXISTS post_theme_id TEXT,
  ADD COLUMN IF NOT EXISTS post_theme_name TEXT,
  ADD COLUMN IF NOT EXISTS post_answers TEXT[],
  ADD COLUMN IF NOT EXISTS post_answers_contain_questions BOOLEAN;
ALTER TABLE savy.reminders DROP CONSTRAINT IF EXISTS reminders_kind_check;
ALTER TABLE savy.reminders ADD CONSTRAINT reminders_kind_check
  CHECK (kind IN ('reminder', 'action', 'event', 'post'));
COMMIT;
