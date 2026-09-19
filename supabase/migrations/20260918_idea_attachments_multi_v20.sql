-- WHYNOT V20: incremental normalized multi-file idea reference metadata.
-- Prerequisite: the private idea-pdfs bucket already allows PDF/PNG/JPEG.
-- Existing Storage objects and ideas.pdf_attachment_* columns are retained.
BEGIN;

CREATE TABLE IF NOT EXISTS public.idea_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id TEXT NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  idea_id TEXT NOT NULL,
  storage_path TEXT NOT NULL UNIQUE,
  original_name TEXT NOT NULL,
  mime_type TEXT NOT NULL CHECK (mime_type IN ('application/pdf', 'image/png', 'image/jpeg')),
  file_size BIGINT NOT NULL CHECK (file_size > 0 AND file_size <= 10485760),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT idea_attachments_idea_room_fk
    FOREIGN KEY (idea_id, room_id)
    REFERENCES public.ideas(id, room_id)
    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idea_attachments_idea_created_idx
  ON public.idea_attachments (idea_id, created_at, id);

ALTER TABLE public.idea_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.idea_attachments FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.idea_attachments FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.idea_attachments TO service_role;

CREATE OR REPLACE FUNCTION public.enforce_idea_attachment_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(NEW.idea_id));
  IF (SELECT COUNT(*) FROM public.idea_attachments WHERE idea_id = NEW.idea_id) >= 3 THEN
    RAISE EXCEPTION '참고 자료는 아이디어당 최대 3개까지 첨부할 수 있습니다.' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS idea_attachments_limit_trg ON public.idea_attachments;
CREATE TRIGGER idea_attachments_limit_trg
BEFORE INSERT ON public.idea_attachments
FOR EACH ROW EXECUTE FUNCTION public.enforce_idea_attachment_limit();

REVOKE ALL ON FUNCTION public.enforce_idea_attachment_limit() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_idea_attachment_limit() TO service_role;

-- Register existing real files without moving, renaming, or deleting objects.
-- A missing legacy size is represented as 1 byte because the original object
-- remains authoritative and the legacy schema permitted a nullable size.
INSERT INTO public.idea_attachments (
  room_id, idea_id, storage_path, original_name, mime_type, file_size, created_at
)
SELECT
  i.room_id,
  i.id,
  i.pdf_attachment_path,
  COALESCE(NULLIF(i.pdf_attachment_name, ''), '참고 자료.pdf'),
  CASE
    WHEN LOWER(i.pdf_attachment_path) LIKE '%.png' THEN 'image/png'
    WHEN LOWER(i.pdf_attachment_path) LIKE '%.jpg'
      OR LOWER(i.pdf_attachment_path) LIKE '%.jpeg' THEN 'image/jpeg'
    ELSE 'application/pdf'
  END,
  COALESCE(i.pdf_attachment_size, 1),
  COALESCE(i.created_at, NOW())
FROM public.ideas i
WHERE i.pdf_attachment_path IS NOT NULL
ON CONFLICT (storage_path) DO NOTHING;

COMMIT;
