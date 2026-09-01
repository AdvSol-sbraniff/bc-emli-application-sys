-- ============================================================
-- Claims AI test harness
--
-- Run this file immediately after 2_create_schema.sql. It is
-- intentionally standalone and idempotent so it can also be run
-- against an existing claims schema.
-- ============================================================

BEGIN;

-- ============================================================
-- testsuites
-- PURPOSE: Reusable business groupings of trusted baseline cases.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.testsuites (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  description text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT testsuites_pkey PRIMARY KEY (id),
  CONSTRAINT testsuites_name_uniq UNIQUE (name),
  CONSTRAINT testsuites_name_present_chk
    CHECK (btrim(name) <> '')
);

COMMENT ON TABLE claims.testsuites IS
  'Reusable groupings of accepted invoice packages for model comparison, rule comparison, and regression testing.';

-- ============================================================
-- testsuite_cases
-- PURPOSE: One trusted baseline invoice package within a suite.
-- The baseline evidence is the accepted invoice_version and its children.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.testsuite_cases (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  testsuite_id uuid NOT NULL,
  baseline_invoice_version_id uuid NOT NULL,
  baseline_ingest_run_id uuid NOT NULL,

  name character varying(200) NOT NULL,
  description text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT testsuite_cases_pkey PRIMARY KEY (id),
  CONSTRAINT testsuite_cases_name_uniq
    UNIQUE (testsuite_id, name),
  CONSTRAINT testsuite_cases_suite_baseline_uniq
    UNIQUE (testsuite_id, baseline_invoice_version_id),
  -- Supports the run-case composite FK that prevents baseline substitution.
  CONSTRAINT testsuite_cases_id_baseline_uniq
    UNIQUE (id, baseline_invoice_version_id, baseline_ingest_run_id),
  CONSTRAINT testsuite_cases_name_present_chk
    CHECK (btrim(name) <> ''),

  CONSTRAINT fk_testsuite_cases_suite
    FOREIGN KEY (testsuite_id)
    REFERENCES claims.testsuites(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_testsuite_cases_baseline_version
    FOREIGN KEY (baseline_invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testsuite_cases_baseline_ingest_run
    FOREIGN KEY (baseline_ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE RESTRICT
);

COMMENT ON TABLE claims.testsuite_cases IS
  'Accepted baseline invoice packages with the exact ingest run that produced the trusted baseline.';

CREATE INDEX IF NOT EXISTS idx_testsuite_cases_baseline_version
  ON claims.testsuite_cases (baseline_invoice_version_id);

CREATE INDEX IF NOT EXISTS idx_testsuite_cases_baseline_ingest_run
  ON claims.testsuite_cases (baseline_ingest_run_id);


-- ============================================================
-- testrunmodelcompares
-- PURPOSE: One validated model-comparison definition and execution.
-- Deployment fields are immutable run snapshots, not live System Config values.
-- Before inserting this row, the application verifies that every case in the
-- selected suite has the same three baseline deployments in its exact
-- baseline ingest run. Creation fails if any case is missing provenance or
-- does not match; incompatible cases are never silently skipped. No case
-- execution rows are created at this stage.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.testrunmodelcompares (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  testsuite_id uuid NOT NULL,
  status character varying(30) NOT NULL DEFAULT 'draft',

  -- The baseline values are derived from and validated against every suite
  -- case when this comparison record is created.
  baseline_document_triage_deployment_name character varying(200) NOT NULL,
  baseline_supporting_document_extraction_deployment_name character varying(200) NOT NULL,
  baseline_upgrade_analysis_deployment_name character varying(200) NOT NULL,

  -- Frozen candidate configuration selected for this comparison. Resulting
  -- candidate ingest_runs record the deployments actually used per case.
  candidate_document_triage_deployment_name character varying(200) NOT NULL,
  candidate_supporting_document_extraction_deployment_name character varying(200) NOT NULL,
  candidate_upgrade_analysis_deployment_name character varying(200) NOT NULL,
  comparison_deployment_name character varying(200) NOT NULL,

  -- One finalization LLM call reviews all completed case-level comparisons and
  -- writes these three suite-wide analyses using comparison_deployment_name.
  overall_document_classification_comparison text NULL,
  overall_supporting_document_extraction_comparison text NULL,
  overall_upgrade_analysis_comparison text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT testrunmodelcompares_pkey PRIMARY KEY (id),
  CONSTRAINT testrunmodelcompares_status_chk
    CHECK (
      status IN ('draft','queued','running','completed','failed','cancelled')
    ),
  CONSTRAINT testrunmodelcompares_deployments_present_chk
    CHECK (
      btrim(baseline_document_triage_deployment_name) <> ''
      AND btrim(baseline_supporting_document_extraction_deployment_name) <> ''
      AND btrim(baseline_upgrade_analysis_deployment_name) <> ''
      AND btrim(candidate_document_triage_deployment_name) <> ''
      AND btrim(candidate_supporting_document_extraction_deployment_name) <> ''
      AND btrim(candidate_upgrade_analysis_deployment_name) <> ''
      AND btrim(comparison_deployment_name) <> ''
    ),
  CONSTRAINT testrunmodelcompares_completed_comparisons_chk
    CHECK (
      status <> 'completed'
      OR (
        NULLIF(btrim(overall_document_classification_comparison), '') IS NOT NULL
        AND NULLIF(btrim(overall_supporting_document_extraction_comparison), '') IS NOT NULL
        AND NULLIF(btrim(overall_upgrade_analysis_comparison), '') IS NOT NULL
      )
    ),

  CONSTRAINT fk_testrunmodelcompares_suite
    FOREIGN KEY (testsuite_id)
    REFERENCES claims.testsuites(id)
    ON DELETE RESTRICT
);

COMMENT ON TABLE claims.testrunmodelcompares IS
  'Validated model comparisons with frozen baseline, candidate, and evaluator deployments.';

CREATE INDEX IF NOT EXISTS idx_testrunmodelcompares_suite_created
  ON claims.testrunmodelcompares (testsuite_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_testrunmodelcompares_status_created
  ON claims.testrunmodelcompares (status, created_at DESC);


-- ============================================================
-- testrunmodelcompare_cases
-- PURPOSE: One actual model-comparison package execution created while the
-- parent comparison runs. This is execution output, not a suite snapshot.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.testrunmodelcompare_cases (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  testrunmodelcompare_id uuid NOT NULL,
  testsuite_case_id uuid NOT NULL,

  baseline_invoice_version_id uuid NOT NULL,
  baseline_ingest_run_id uuid NOT NULL,
  candidate_invoice_version_id uuid NULL,
  candidate_ingest_run_id uuid NULL,

  status character varying(30) NOT NULL DEFAULT 'queued',

  document_classification_comparison text NULL,
  supporting_document_extraction_comparison text NULL,
  upgrade_analysis_comparison text NULL,

  failure_code character varying(100) NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT testrunmodelcompare_cases_pkey PRIMARY KEY (id),
  CONSTRAINT testrunmodelcompare_cases_run_case_uniq
    UNIQUE (testrunmodelcompare_id, testsuite_case_id),
  CONSTRAINT testrunmodelcompare_cases_status_chk
    CHECK (status IN ('queued','running','completed','failed','skipped','cancelled')),
  CONSTRAINT testrunmodelcompare_cases_failure_code_chk
    CHECK (
      failure_code IS NULL
      OR failure_code IN (
        'baseline_unavailable',
        'configuration_invalid',
        'candidate_run_creation_failed',
        'candidate_processing_failed',
        'comparison_failed',
        'internal_error'
      )
    ),
  CONSTRAINT testrunmodelcompare_cases_failure_status_chk
    CHECK (
      (status = 'failed' AND failure_code IS NOT NULL)
      OR (status <> 'failed' AND failure_code IS NULL)
    ),
  CONSTRAINT testrunmodelcompare_cases_distinct_versions_chk
    CHECK (
      candidate_invoice_version_id IS NULL
      OR candidate_invoice_version_id <> baseline_invoice_version_id
    ),

  CONSTRAINT fk_testrunmodelcompare_cases_run
    FOREIGN KEY (testrunmodelcompare_id)
    REFERENCES claims.testrunmodelcompares(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_testrunmodelcompare_cases_case_baseline
    FOREIGN KEY (
      testsuite_case_id,
      baseline_invoice_version_id,
      baseline_ingest_run_id
    )
    REFERENCES claims.testsuite_cases(
      id,
      baseline_invoice_version_id,
      baseline_ingest_run_id
    )
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunmodelcompare_cases_baseline_version
    FOREIGN KEY (baseline_invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunmodelcompare_cases_baseline_ingest_run
    FOREIGN KEY (baseline_ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunmodelcompare_cases_candidate_version
    FOREIGN KEY (candidate_invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunmodelcompare_cases_candidate_ingest_run
    FOREIGN KEY (candidate_ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE SET NULL
);

COMMENT ON TABLE claims.testrunmodelcompare_cases IS
  'Model-comparison package executions with three readable evaluator analyses.';

CREATE INDEX IF NOT EXISTS idx_testrunmodelcompare_cases_run_status
  ON claims.testrunmodelcompare_cases (
    testrunmodelcompare_id,
    status,
    created_at DESC
  );

CREATE INDEX IF NOT EXISTS idx_testrunmodelcompare_cases_suite_case
  ON claims.testrunmodelcompare_cases (testsuite_case_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_testrunmodelcompare_cases_candidate_version
  ON claims.testrunmodelcompare_cases (candidate_invoice_version_id)
  WHERE candidate_invoice_version_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_testrunmodelcompare_cases_baseline_ingest_run
  ON claims.testrunmodelcompare_cases (baseline_ingest_run_id);

CREATE INDEX IF NOT EXISTS idx_testrunmodelcompare_cases_candidate_ingest_run
  ON claims.testrunmodelcompare_cases (candidate_ingest_run_id)
  WHERE candidate_ingest_run_id IS NOT NULL;


-- ============================================================
-- RULE COMPARISON
--
-- claims.testrunrulecompares is the parent
-- run table. candidate_genai_rule_id identifies the current registry rule
-- whose behavior is being tested against the accepted baseline evidence.
--
-- Before creating a rule-comparison record, every suite invoice version must
-- use the selected logical rule at least once: it MUST contain at least one
-- GenAI invoice_version_rulechecks row whose immutable rule_key matches the
-- selected candidate genai_rules.genai_rule_key. Creation fails if any suite
-- case is missing that rule; cases are never silently skipped.
--
-- The baseline is the accepted invoice-version result for the immutable
-- rule_key. Rule-history records are not selected after processing because an
-- ingest run does not persist a rule-history UUID. Candidate executions retain
-- the exact prompt actually used in their ingest-step context snapshots.
--
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.testrunrulecompares (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  testsuite_id uuid NOT NULL,
  candidate_genai_rule_id uuid NOT NULL,
  status character varying(30) NOT NULL DEFAULT 'draft',
  comparison_deployment_name character varying(200) NOT NULL,

  -- One finalization LLM call reviews all completed case-level rule
  -- comparisons and writes the suite-wide conclusion here.
  overall_rule_comparison text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT testrunrulecompares_pkey PRIMARY KEY (id),
  CONSTRAINT testrunrulecompares_status_chk
    CHECK (
      status IN ('draft','queued','running','completed','failed','cancelled')
    ),
  CONSTRAINT testrunrulecompares_deployment_present_chk
    CHECK (btrim(comparison_deployment_name) <> ''),
  CONSTRAINT testrunrulecompares_completed_comparison_chk
    CHECK (
      status <> 'completed'
      OR NULLIF(btrim(overall_rule_comparison), '') IS NOT NULL
    ),
  CONSTRAINT fk_testrunrulecompares_suite
    FOREIGN KEY (testsuite_id)
    REFERENCES claims.testsuites(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunrulecompares_candidate_rule
    FOREIGN KEY (candidate_genai_rule_id)
    REFERENCES claims.genai_rules(id)
    ON DELETE RESTRICT
);

COMMENT ON TABLE claims.testrunrulecompares IS
  'Validated single-rule comparisons between accepted baseline evidence and the selected current rule.';

CREATE INDEX IF NOT EXISTS idx_testrunrulecompares_suite_created
  ON claims.testrunrulecompares (testsuite_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_testrunrulecompares_status_created
  ON claims.testrunrulecompares (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_testrunrulecompares_candidate_rule
  ON claims.testrunrulecompares (candidate_genai_rule_id);

-- ============================================================
-- testrunrulecompare_cases
-- PURPOSE: One package execution for one changed GenAI rule.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.testrunrulecompare_cases (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  testrunrulecompare_id uuid NOT NULL,
  testsuite_case_id uuid NOT NULL,

  baseline_invoice_version_id uuid NOT NULL,
  baseline_ingest_run_id uuid NOT NULL,
  candidate_invoice_version_id uuid NULL,
  candidate_ingest_run_id uuid NULL,

  status character varying(30) NOT NULL DEFAULT 'queued',
  rule_comparison text NULL,
  failure_code character varying(100) NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT testrunrulecompare_cases_pkey PRIMARY KEY (id),
  CONSTRAINT testrunrulecompare_cases_run_case_uniq
    UNIQUE (testrunrulecompare_id, testsuite_case_id),
  CONSTRAINT testrunrulecompare_cases_status_chk
    CHECK (status IN ('queued','running','completed','failed','skipped','cancelled')),
  CONSTRAINT testrunrulecompare_cases_failure_code_chk
    CHECK (
      failure_code IS NULL
      OR failure_code IN (
        'baseline_unavailable',
        'configuration_invalid',
        'candidate_run_creation_failed',
        'candidate_processing_failed',
        'comparison_failed',
        'internal_error'
      )
    ),
  CONSTRAINT testrunrulecompare_cases_failure_status_chk
    CHECK (
      (status = 'failed' AND failure_code IS NOT NULL)
      OR (status <> 'failed' AND failure_code IS NULL)
    ),
  CONSTRAINT testrunrulecompare_cases_distinct_versions_chk
    CHECK (
      candidate_invoice_version_id IS NULL
      OR candidate_invoice_version_id <> baseline_invoice_version_id
    ),

  CONSTRAINT fk_testrunrulecompare_cases_run
    FOREIGN KEY (testrunrulecompare_id)
    REFERENCES claims.testrunrulecompares(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_testrunrulecompare_cases_case_baseline
    FOREIGN KEY (
      testsuite_case_id,
      baseline_invoice_version_id,
      baseline_ingest_run_id
    )
    REFERENCES claims.testsuite_cases(
      id,
      baseline_invoice_version_id,
      baseline_ingest_run_id
    )
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunrulecompare_cases_baseline_version
    FOREIGN KEY (baseline_invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunrulecompare_cases_baseline_ingest_run
    FOREIGN KEY (baseline_ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunrulecompare_cases_candidate_version
    FOREIGN KEY (candidate_invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunrulecompare_cases_candidate_ingest_run
    FOREIGN KEY (candidate_ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE SET NULL
);

COMMENT ON TABLE claims.testrunrulecompare_cases IS
  'Single-rule comparison package executions with one readable evaluator analysis.';

CREATE INDEX IF NOT EXISTS idx_testrunrulecompare_cases_run_status
  ON claims.testrunrulecompare_cases (
    testrunrulecompare_id,
    status,
    created_at DESC
  );

CREATE INDEX IF NOT EXISTS idx_testrunrulecompare_cases_suite_case
  ON claims.testrunrulecompare_cases (testsuite_case_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_testrunrulecompare_cases_candidate_version
  ON claims.testrunrulecompare_cases (candidate_invoice_version_id)
  WHERE candidate_invoice_version_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_testrunrulecompare_cases_baseline_ingest_run
  ON claims.testrunrulecompare_cases (baseline_ingest_run_id);

CREATE INDEX IF NOT EXISTS idx_testrunrulecompare_cases_candidate_ingest_run
  ON claims.testrunrulecompare_cases (candidate_ingest_run_id)
  WHERE candidate_ingest_run_id IS NOT NULL;


-- ============================================================
-- REGRESSION
-- PURPOSE: Full-pipeline stability runs. Regression is not a
-- baseline/candidate comparison; every case is processed once using the
-- deployments frozen on the parent run.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.testrunregressions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  testsuite_id uuid NOT NULL,
  status character varying(30) NOT NULL DEFAULT 'draft',
  document_triage_deployment_name character varying(200) NOT NULL,
  supporting_document_extraction_deployment_name character varying(200) NOT NULL,
  upgrade_analysis_deployment_name character varying(200) NOT NULL,
  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT testrunregressions_pkey PRIMARY KEY (id),
  CONSTRAINT testrunregressions_status_chk
    CHECK (
      status IN ('draft','queued','running','completed','failed','cancelled')
    ),
  CONSTRAINT testrunregressions_deployments_present_chk
    CHECK (
      btrim(document_triage_deployment_name) <> ''
      AND btrim(supporting_document_extraction_deployment_name) <> ''
      AND btrim(upgrade_analysis_deployment_name) <> ''
    ),
  CONSTRAINT fk_testrunregressions_suite
    FOREIGN KEY (testsuite_id)
    REFERENCES claims.testsuites(id)
    ON DELETE RESTRICT
);

COMMENT ON TABLE claims.testrunregressions IS
  'Full-pipeline regression runs with frozen business-call deployments.';

CREATE INDEX IF NOT EXISTS idx_testrunregressions_suite_created
  ON claims.testrunregressions (testsuite_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_testrunregressions_status_created
  ON claims.testrunregressions (status, created_at DESC);

-- ============================================================
-- testrunregression_cases
-- PURPOSE: One complete release-regression package execution.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.testrunregression_cases (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  testrunregression_id uuid NOT NULL,
  testsuite_case_id uuid NOT NULL,

  invoice_version_id uuid NULL,
  ingest_run_id uuid NULL,

  status character varying(30) NOT NULL DEFAULT 'queued',
  result_summary text NULL,
  failure_code character varying(100) NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT testrunregression_cases_pkey PRIMARY KEY (id),
  CONSTRAINT testrunregression_cases_run_case_uniq
    UNIQUE (testrunregression_id, testsuite_case_id),
  CONSTRAINT testrunregression_cases_status_chk
    CHECK (status IN ('queued','running','completed','failed','skipped','cancelled')),
  CONSTRAINT testrunregression_cases_failure_code_chk
    CHECK (
      failure_code IS NULL
      OR failure_code IN (
        'source_unavailable',
        'configuration_invalid',
        'ingest_run_creation_failed',
        'processing_failed',
        'expectation_failed',
        'internal_error'
      )
    ),
  CONSTRAINT testrunregression_cases_failure_status_chk
    CHECK (
      (status = 'failed' AND failure_code IS NOT NULL)
      OR (status <> 'failed' AND failure_code IS NULL)
    ),
  CONSTRAINT testrunregression_cases_completed_execution_chk
    CHECK (
      status <> 'completed'
      OR (invoice_version_id IS NOT NULL AND ingest_run_id IS NOT NULL)
    ),

  CONSTRAINT fk_testrunregression_cases_run
    FOREIGN KEY (testrunregression_id)
    REFERENCES claims.testrunregressions(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_testrunregression_cases_suite_case
    FOREIGN KEY (testsuite_case_id)
    REFERENCES claims.testsuite_cases(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunregression_cases_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_testrunregression_cases_ingest_run
    FOREIGN KEY (ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE RESTRICT
);

COMMENT ON TABLE claims.testrunregression_cases IS
  'Full-pipeline stability executions used to detect crashes and broad processing failures.';

CREATE INDEX IF NOT EXISTS idx_testrunregression_cases_run_status
  ON claims.testrunregression_cases (
    testrunregression_id,
    status,
    created_at DESC
  );

CREATE INDEX IF NOT EXISTS idx_testrunregression_cases_suite_case
  ON claims.testrunregression_cases (testsuite_case_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_testrunregression_cases_invoice_version
  ON claims.testrunregression_cases (invoice_version_id)
  WHERE invoice_version_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_testrunregression_cases_ingest_run
  ON claims.testrunregression_cases (ingest_run_id)
  WHERE ingest_run_id IS NOT NULL;

COMMIT;
