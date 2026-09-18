\set ON_ERROR_STOP on

-- Additive local patch only. The main rebuild DDL already includes this column.
DO $$
BEGIN
  IF current_database() NOT IN ('app_development', 'app_test') THEN
    RAISE EXCEPTION 'This helper is restricted to local app_development/app_test databases';
  END IF;
END $$;

BEGIN;
ALTER TABLE claims.validationgenai_config
  ADD COLUMN IF NOT EXISTS rule_audit_system_record text NULL;
COMMENT ON COLUMN claims.validationgenai_config.rule_audit_system_record IS
  'Editable single-package rule audit instruction. NULL/blank uses config/prompts/rule_package_audit_system.txt. Audits use comparison_deployment_name.';
COMMIT;
