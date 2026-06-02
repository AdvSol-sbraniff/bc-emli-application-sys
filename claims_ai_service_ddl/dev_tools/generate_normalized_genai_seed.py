from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_SQL = ROOT / "5_insert_validationgenai_rulesets.sql"
TARGET_SQL = ROOT / "5_insert_genai_normalized.sql"

RETIRED_GENAI_RULE_KEYS = (
    "ashp_electric_product_reference_present",
    "ashp_gas_propane_product_reference_present",
    "ashp_oil_product_reference_present",
    "ashp_wood_product_reference_present",
    "atw_product_reference_present",
    "cshp_product_reference_present",
    "hp_product_reference_present",
    "hydronic_product_reference_present",
    "income_level_allows_rebate",
    "wd_income_level_and_vancouver_review",
)

FIELD_CONFLICT_OVERRIDES = {
    "upgrade_specific_rebate_line_amount": (
        "Locate the CleanBC/Better Homes/ESP rebate amount for this specific upgrade only."
    ),
    "hp_new_equipment_type": (
        "Locate single-head mini-split, 2-head/multi-split, ductless mini-split, "
        "ductless multi-split, central ducted, low-static ducted mini, indoor "
        "heads/zones, or similar."
    ),
    "hp_ahri_reference": (
        'Locate AHRI reference/certificate numbers for outdoor unit, indoor unit(s), '
        'and furnace where visible. Store only the numeric AHRI reference number in '
        'value, such as "213617706"; put the full visible invoice phrase, such as '
        '"AHRI Certificate: 213617706", in evidence_text.'
    ),
    "hp_product_list_reference": (
        "Locate qualified heat pump product list, NRCan, ENERGY STAR, NEEP, NRCan "
        "Oil to Heat Pump Affordability qualified product list, or similar references."
    ),
}

RULE_CANONICAL_KEYS = {
    frozenset(
        {
            "ashp_electric_description_sufficient_for_review",
            "ashp_gas_propane_description_sufficient_for_review",
            "ashp_oil_description_sufficient_for_review",
            "ashp_wood_description_sufficient_for_review",
            "atw_description_sufficient_for_review",
            "cshp_description_sufficient_for_review",
        }
    ): "hp_description_sufficient_for_review",
    frozenset(
        {
            "ashp_gas_propane_backup_not_fossil_primary",
            "ashp_oil_backup_not_fossil_primary",
        }
    ): "hp_fossil_backup_not_fossil_primary",
    frozenset(
        {
            "ashp_gas_propane_no_existing_heat_pump_flag",
            "ashp_oil_no_existing_heat_pump_flag",
        }
    ): "hp_fossil_no_existing_heat_pump_flag",
    frozenset(
        {
            "atw_conversion_context_present",
            "cshp_conversion_context_present",
        }
    ): "hydronic_conversion_context_present",
    frozenset(
        {
            "atw_no_existing_heat_pump_flag",
            "cshp_no_existing_heat_pump_flag",
        }
    ): "hydronic_no_existing_heat_pump_flag",
}

FIELD_CANONICAL_KEYS = {
    frozenset(
        {
            "atw_existing_heat_pump_flag",
            "cshp_existing_heat_pump_flag",
            "hp_existing_heat_pump_flag",
        }
    ): "hp_existing_heat_pump_flag",
    frozenset(
        {
            "atw_heat_load_calc_reference",
            "cshp_heat_load_calc_reference",
            "hp_heat_load_calc_reference",
        }
    ): "hp_heat_load_calc_reference",
    frozenset(
        {
            "atw_make_model",
            "cshp_make_model",
            "hp_make_model",
        }
    ): "hp_make_model",
    frozenset(
        {
            "atw_northern_top_up_evidence",
            "cshp_northern_top_up_evidence",
            "dfhp_northern_top_up_evidence",
            "hp_northern_top_up_evidence",
        }
    ): "hp_northern_top_up_evidence",
    frozenset(
        {
            "atw_non_integrated_area_preapproval_reference",
            "cshp_non_integrated_area_preapproval_reference",
            "hp_non_integrated_area_preapproval_reference",
        }
    ): "hp_non_integrated_area_preapproval_reference",
    frozenset(
        {
            "dfhp_registered_contractor_or_permit_evidence",
            "hp_registered_contractor_or_permit_evidence",
            "hpwh_registered_contractor_or_permit_evidence",
        }
    ): "hp_registered_contractor_or_permit_evidence",
    frozenset(
        {
            "atw_conversion_source_fuel_evidence",
            "cshp_conversion_source_fuel_evidence",
        }
    ): "hydronic_conversion_source_fuel_evidence",
    frozenset(
        {
            "atw_fossil_removal_evidence",
            "cshp_fossil_removal_evidence",
        }
    ): "hydronic_fossil_removal_evidence",
    frozenset(
        {
            "atw_wood_removal_or_wett_evidence",
            "cshp_wood_removal_or_wett_evidence",
        }
    ): "hydronic_wood_removal_or_wett_evidence",
    frozenset(
        {
            "hs_before_after_photo_reference",
            "ins_before_after_photo_reference",
        }
    ): "before_after_photo_reference",
}

RULE_SECTION_MARKERS = (
    "Common GenAI rulecheck tasks:",
    "GenAI/manual-review rulecheck tasks:",
    "GenAI rulecheck tasks:",
    "Rulecheck tasks:",
)


def canonicalize_key(key: str, mapping: dict[frozenset[str], str]) -> str:
    for aliases, canonical_key in mapping.items():
        if key in aliases:
            return canonical_key
    return key


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def find_ruleset_blocks(text: str) -> list[tuple[str, str]]:
    blocks: list[tuple[str, str]] = []

    common_match = re.search(
        r"common_ruleset_row\s*\(\s*user_record1\s*\)\s*AS\s*\(\s*VALUES\s*\(\s*\$([A-Za-z0-9_]+)\$(.*?)\$\1\$",
        text,
        re.S,
    )
    if common_match:
        blocks.append(("common", common_match.group(2)))

    pattern = re.compile(
        r"\(\s*'[^']+'::uuid,\s*'([^']+)',\s*'[^']+',\s*\$([A-Za-z0-9_]+)\$(.*?)\$\2\$",
        re.S,
    )
    blocks.extend((m.group(1), m.group(3)) for m in pattern.finditer(text))
    return blocks


def field_section(blob: str) -> str:
    lower = blob.lower()
    start = lower.find("located fields:")
    if start == -1:
        return ""
    start = blob.find("\n", start)
    if start == -1:
        return ""
    start += 1
    end_positions = [blob.find(marker, start) for marker in RULE_SECTION_MARKERS if blob.find(marker, start) != -1]
    end = min(end_positions) if end_positions else len(blob)
    return blob[start:end].strip()


def rule_section(blob: str) -> str:
    starts = [blob.find(marker) for marker in RULE_SECTION_MARKERS if blob.find(marker) != -1]
    if not starts:
        return ""
    start = min(starts)
    start = blob.find("\n", start)
    if start == -1:
        return ""
    return blob[start + 1 :].strip()


def parse_fields(blob: str) -> list[tuple[int, str, str]]:
    section = field_section(blob)
    if not section:
        return []
    pattern = re.compile(
        r"(?ms)^\s*(\d+)\s+\[field_key:\s*([^\]]+)\]\s*(.*?)(?=^\s*\d+\s+\[field_key:|\Z)"
    )
    rows = []
    for match in pattern.finditer(section):
        number = int(match.group(1))
        key = match.group(2).strip()
        prompt_text = match.group(3).strip()
        rows.append((number, key, prompt_text))
    return rows


def parse_rules(blob: str) -> list[tuple[int, str, str]]:
    section = rule_section(blob)
    if not section:
        return []
    pattern = re.compile(
        r"(?ms)^\s*rule\s+(\d+)\s+\[rule_key:\s*([^\]]+)\]\s*\n(.*?)(?=^\s*rule\s+\d+\s+\[rule_key:|\Z)"
    )
    rows = []
    for match in pattern.finditer(section):
        number = int(match.group(1))
        key = match.group(2).strip()
        prompt_text = match.group(3).strip()
        rows.append((number, key, prompt_text))
    return rows


def build() -> str:
    text = SOURCE_SQL.read_text(encoding="utf-8")
    blocks = find_ruleset_blocks(text)

    field_defs: dict[str, str] = {}
    field_mappings: list[tuple[str, str, int]] = []
    field_seen: dict[str, set[str]] = defaultdict(set)

    rule_defs: dict[str, str] = {}
    rule_mappings: list[tuple[str, str, int]] = []
    rule_seen: dict[str, set[str]] = defaultdict(set)

    for upgrade_type_key, blob in blocks:
        for field_number, field_key, prompt_text in parse_fields(blob):
            field_key = canonicalize_key(field_key, FIELD_CANONICAL_KEYS)
            field_seen[field_key].add(prompt_text)
            field_mappings.append((upgrade_type_key, field_key, field_number))
        for rule_number, rule_key, prompt_text in parse_rules(blob):
            rule_key = canonicalize_key(rule_key, RULE_CANONICAL_KEYS)
            rule_seen[rule_key].add(prompt_text)
            rule_mappings.append((upgrade_type_key, rule_key, rule_number))

    for field_key, prompts in field_seen.items():
        if len(prompts) == 1:
            field_defs[field_key] = next(iter(prompts))
        elif field_key in FIELD_CONFLICT_OVERRIDES:
            field_defs[field_key] = FIELD_CONFLICT_OVERRIDES[field_key]
        else:
            raise RuntimeError(f"Unhandled field prompt conflict for {field_key}: {len(prompts)} variants")

    for rule_key, prompts in rule_seen.items():
        if len(prompts) != 1:
            raise RuntimeError(f"Unhandled rule prompt conflict for {rule_key}: {len(prompts)} variants")
        rule_defs[rule_key] = next(iter(prompts))

    lines: list[str] = []
    lines.append("BEGIN;")
    lines.append("")
    lines.append("-- Retired GenAI rules now handled by deterministic code rules or narrower prompts.")
    lines.append("-- Delete before inserting current mappings so old rule-order slots do not conflict.")
    lines.append("DELETE FROM claims.genai_rules")
    lines.append("WHERE genai_rule_key IN (")
    for idx, rule_key in enumerate(RETIRED_GENAI_RULE_KEYS):
        comma = "," if idx < len(RETIRED_GENAI_RULE_KEYS) - 1 else ""
        lines.append(f"  {sql_quote(rule_key)}{comma}")
    lines.append(");")
    lines.append("")
    lines.append("WITH genai_rules_seed (")
    lines.append("  genai_rule_key,")
    lines.append("  prompt_text,")
    lines.append("  enabled,")
    lines.append("  created_at,")
    lines.append("  updated_at")
    lines.append(") AS (")
    lines.append("  VALUES")
    rule_items = sorted(rule_defs.items())
    for idx, (rule_key, prompt_text) in enumerate(rule_items):
        comma = "," if idx < len(rule_items) - 1 else ""
        lines.append(
            f"  ({sql_quote(rule_key)}, {sql_quote(prompt_text)}, true, TIMESTAMP '2026-05-26 00:00:00', NOW()){comma}"
        )
    lines.append(")")
    lines.append("INSERT INTO claims.genai_rules (")
    lines.append("  genai_rule_key,")
    lines.append("  prompt_text,")
    lines.append("  enabled,")
    lines.append("  created_at,")
    lines.append("  updated_at")
    lines.append(")")
    lines.append("SELECT")
    lines.append("  genai_rule_key,")
    lines.append("  prompt_text,")
    lines.append("  enabled,")
    lines.append("  created_at,")
    lines.append("  updated_at")
    lines.append("FROM genai_rules_seed")
    lines.append("ON CONFLICT (genai_rule_key) DO UPDATE SET")
    lines.append("  prompt_text = EXCLUDED.prompt_text,")
    lines.append("  updated_at = NOW();")
    lines.append("")
    lines.append("WITH genai_rule_upgrade_types_seed (")
    lines.append("  upgrade_type_key,")
    lines.append("  genai_rule_key,")
    lines.append("  rule_number")
    lines.append(") AS (")
    lines.append("  VALUES")
    rule_maps = sorted(rule_mappings)
    for idx, (upgrade_type_key, rule_key, rule_number) in enumerate(rule_maps):
        comma = "," if idx < len(rule_maps) - 1 else ""
        lines.append(
            f"  ({sql_quote(upgrade_type_key)}, {sql_quote(rule_key)}, {rule_number}){comma}"
        )
    lines.append(")")
    lines.append("INSERT INTO claims.genai_rule_upgrade_types (")
    lines.append("  genai_rule_id,")
    lines.append("  invoice_upgrade_type_id,")
    lines.append("  rule_number,")
    lines.append("  created_at,")
    lines.append("  updated_at")
    lines.append(")")
    lines.append("SELECT")
    lines.append("  gr.id,")
    lines.append("  iut.id,")
    lines.append("  seed.rule_number,")
    lines.append("  NOW(),")
    lines.append("  NOW()")
    lines.append("FROM genai_rule_upgrade_types_seed seed")
    lines.append("JOIN claims.genai_rules gr")
    lines.append("  ON gr.genai_rule_key = seed.genai_rule_key")
    lines.append("JOIN claims.invoice_upgrade_types iut")
    lines.append("  ON iut.upgrade_type_key = seed.upgrade_type_key")
    lines.append("ON CONFLICT (genai_rule_id, invoice_upgrade_type_id) DO UPDATE SET")
    lines.append("  rule_number = EXCLUDED.rule_number,")
    lines.append("  updated_at = NOW();")
    lines.append("")
    lines.append("WITH genai_located_fields_seed (")
    lines.append("  genai_field_key,")
    lines.append("  prompt_text,")
    lines.append("  enabled,")
    lines.append("  created_at,")
    lines.append("  updated_at")
    lines.append(") AS (")
    lines.append("  VALUES")
    field_items = sorted(field_defs.items())
    for idx, (field_key, prompt_text) in enumerate(field_items):
        comma = "," if idx < len(field_items) - 1 else ""
        lines.append(
            f"  ({sql_quote(field_key)}, {sql_quote(prompt_text)}, true, TIMESTAMP '2026-05-26 00:00:00', NOW()){comma}"
        )
    lines.append(")")
    lines.append("INSERT INTO claims.genai_located_fields (")
    lines.append("  genai_field_key,")
    lines.append("  prompt_text,")
    lines.append("  enabled,")
    lines.append("  created_at,")
    lines.append("  updated_at")
    lines.append(")")
    lines.append("SELECT")
    lines.append("  genai_field_key,")
    lines.append("  prompt_text,")
    lines.append("  enabled,")
    lines.append("  created_at,")
    lines.append("  updated_at")
    lines.append("FROM genai_located_fields_seed")
    lines.append("ON CONFLICT (genai_field_key) DO UPDATE SET")
    lines.append("  prompt_text = EXCLUDED.prompt_text,")
    lines.append("  updated_at = NOW();")
    lines.append("")
    lines.append("WITH genai_located_field_upgrade_types_seed (")
    lines.append("  upgrade_type_key,")
    lines.append("  genai_field_key,")
    lines.append("  field_number")
    lines.append(") AS (")
    lines.append("  VALUES")
    field_maps = sorted(field_mappings)
    for idx, (upgrade_type_key, field_key, field_number) in enumerate(field_maps):
        comma = "," if idx < len(field_maps) - 1 else ""
        lines.append(
            f"  ({sql_quote(upgrade_type_key)}, {sql_quote(field_key)}, {field_number}){comma}"
        )
    lines.append(")")
    lines.append("INSERT INTO claims.genai_located_field_upgrade_types (")
    lines.append("  genai_field_id,")
    lines.append("  invoice_upgrade_type_id,")
    lines.append("  field_number,")
    lines.append("  created_at,")
    lines.append("  updated_at")
    lines.append(")")
    lines.append("SELECT")
    lines.append("  gf.id,")
    lines.append("  iut.id,")
    lines.append("  seed.field_number,")
    lines.append("  NOW(),")
    lines.append("  NOW()")
    lines.append("FROM genai_located_field_upgrade_types_seed seed")
    lines.append("JOIN claims.genai_located_fields gf")
    lines.append("  ON gf.genai_field_key = seed.genai_field_key")
    lines.append("JOIN claims.invoice_upgrade_types iut")
    lines.append("  ON iut.upgrade_type_key = seed.upgrade_type_key")
    lines.append("ON CONFLICT (genai_field_id, invoice_upgrade_type_id) DO UPDATE SET")
    lines.append("  field_number = EXCLUDED.field_number,")
    lines.append("  updated_at = NOW();")
    lines.append("")
    lines.append("COMMIT;")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    TARGET_SQL.write_text(build(), encoding="utf-8")
    print(f"Wrote {TARGET_SQL}")


if __name__ == "__main__":
    main()
