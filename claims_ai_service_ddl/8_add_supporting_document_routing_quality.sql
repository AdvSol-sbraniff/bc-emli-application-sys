BEGIN;

ALTER TABLE claims.supporting_documents
  ADD COLUMN IF NOT EXISTS supplement_routing_quality text,
  ADD COLUMN IF NOT EXISTS supplement_routing_quality_reason text;

ALTER TABLE claims.ingest_documents
  ADD COLUMN IF NOT EXISTS supplement_routing_quality text,
  ADD COLUMN IF NOT EXISTS supplement_routing_quality_reason text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'supporting_documents_routing_quality_chk'
  ) THEN
    ALTER TABLE claims.supporting_documents
      ADD CONSTRAINT supporting_documents_routing_quality_chk
      CHECK (
        supplement_routing_quality IS NULL OR
        supplement_routing_quality IN ('usable','needs_review','requires_visual_review','unusable')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ingest_documents_routing_quality_chk'
  ) THEN
    ALTER TABLE claims.ingest_documents
      ADD CONSTRAINT ingest_documents_routing_quality_chk
      CHECK (
        supplement_routing_quality IS NULL OR
        supplement_routing_quality IN ('usable','needs_review','requires_visual_review','unusable')
      );
  END IF;
END $$;

COMMIT;
