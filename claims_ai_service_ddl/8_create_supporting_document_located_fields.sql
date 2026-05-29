BEGIN;

CREATE TABLE IF NOT EXISTS claims.supporting_document_type_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  supporting_document_type_id uuid NOT NULL,

  field_key text NOT NULL,
  prompt_text text NOT NULL,
  field_number integer NOT NULL,
  enabled boolean NOT NULL DEFAULT true,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT supporting_document_type_located_fields_pkey PRIMARY KEY (id),

  CONSTRAINT fk_supporting_document_type_located_fields_type
    FOREIGN KEY (supporting_document_type_id)
    REFERENCES claims.supporting_document_types(id)
    ON DELETE CASCADE,

  CONSTRAINT supporting_document_type_located_fields_field_number_chk
    CHECK (field_number >= 1),

  CONSTRAINT supporting_document_type_located_fields_key_uniq
    UNIQUE (supporting_document_type_id, field_key),

  CONSTRAINT supporting_document_type_located_fields_order_uniq
    UNIQUE (supporting_document_type_id, field_number)
);

CREATE INDEX IF NOT EXISTS idx_sdtlf_type
  ON claims.supporting_document_type_located_fields (supporting_document_type_id);

CREATE INDEX IF NOT EXISTS idx_sdtlf_enabled
  ON claims.supporting_document_type_located_fields (enabled);


CREATE TABLE IF NOT EXISTS claims.supporting_document_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  supporting_document_id uuid NOT NULL,
  supporting_document_type_located_field_id uuid NULL,

  source_engine text NOT NULL DEFAULT 'genai',
  field_key text NOT NULL,

  value_type text NOT NULL,
  value_text text NULL,
  value_json jsonb NULL,

  confidence smallint NOT NULL DEFAULT 0,

  page integer NULL,
  polygon jsonb NULL,
  evidence_text text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT supporting_document_located_fields_pkey PRIMARY KEY (id),

  CONSTRAINT fk_supporting_document_located_fields_document
    FOREIGN KEY (supporting_document_id)
    REFERENCES claims.supporting_documents(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_supporting_document_located_fields_definition
    FOREIGN KEY (supporting_document_type_located_field_id)
    REFERENCES claims.supporting_document_type_located_fields(id)
    ON DELETE SET NULL,

  CONSTRAINT supporting_document_located_fields_source_engine_chk
    CHECK (source_engine IN ('genai','vision','code','manual')),

  CONSTRAINT supporting_document_located_fields_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),

  CONSTRAINT supporting_document_located_fields_value_type_chk
    CHECK (value_type IN ('text','currency','number','date','bool','json')),

  CONSTRAINT supporting_document_located_fields_value_storage_chk
    CHECK (
      (value_type = 'json' AND value_json IS NOT NULL AND value_text IS NULL)
      OR
      (value_type <> 'json' AND value_text IS NOT NULL AND value_json IS NULL)
      OR
      (value_text IS NULL AND value_json IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_sdlf_document
  ON claims.supporting_document_located_fields (supporting_document_id);

CREATE INDEX IF NOT EXISTS idx_sdlf_definition
  ON claims.supporting_document_located_fields (supporting_document_type_located_field_id);

CREATE INDEX IF NOT EXISTS idx_sdlf_lookup
  ON claims.supporting_document_located_fields (supporting_document_id, field_key);

CREATE INDEX IF NOT EXISTS idx_sdlf_engine
  ON claims.supporting_document_located_fields (supporting_document_id, source_engine);

COMMIT;
