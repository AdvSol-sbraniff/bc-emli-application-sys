BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'supporting_documents'
      AND column_name = 'supplement_routing_quality'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'supporting_documents'
      AND column_name = 'supporting_document_routing_quality'
  ) THEN
    ALTER TABLE claims.supporting_documents
      RENAME COLUMN supplement_routing_quality TO supporting_document_routing_quality;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'supporting_documents'
      AND column_name = 'supplement_routing_quality_reason'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'supporting_documents'
      AND column_name = 'supporting_document_routing_quality_reason'
  ) THEN
    ALTER TABLE claims.supporting_documents
      RENAME COLUMN supplement_routing_quality_reason TO supporting_document_routing_quality_reason;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'ingest_documents'
      AND column_name = 'supplement_routing_quality'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'ingest_documents'
      AND column_name = 'supporting_document_routing_quality'
  ) THEN
    ALTER TABLE claims.ingest_documents
      RENAME COLUMN supplement_routing_quality TO supporting_document_routing_quality;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'ingest_documents'
      AND column_name = 'supplement_routing_quality_reason'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'ingest_documents'
      AND column_name = 'supporting_document_routing_quality_reason'
  ) THEN
    ALTER TABLE claims.ingest_documents
      RENAME COLUMN supplement_routing_quality_reason TO supporting_document_routing_quality_reason;
  END IF;
END $$;

ALTER TABLE claims.supporting_documents
  ADD COLUMN IF NOT EXISTS supporting_document_routing_quality text,
  ADD COLUMN IF NOT EXISTS supporting_document_routing_quality_reason text;

ALTER TABLE claims.ingest_documents
  ADD COLUMN IF NOT EXISTS supporting_document_routing_quality text,
  ADD COLUMN IF NOT EXISTS supporting_document_routing_quality_reason text;

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
        supporting_document_routing_quality IS NULL OR
        supporting_document_routing_quality IN ('usable','needs_review','requires_visual_review','unusable')
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
        supporting_document_routing_quality IS NULL OR
        supporting_document_routing_quality IN ('usable','needs_review','requires_visual_review','unusable')
      );
  END IF;
END $$;

COMMIT;
