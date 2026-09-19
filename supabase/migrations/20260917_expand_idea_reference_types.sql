-- Expand the existing private idea reference bucket without changing idea columns.
-- Existing PDF object paths and metadata remain valid.
BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'idea-pdfs',
  'idea-pdfs',
  false,
  10485760,
  ARRAY['application/pdf', 'image/png', 'image/jpeg']::text[]
)
ON CONFLICT (id) DO UPDATE
SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

COMMIT;
