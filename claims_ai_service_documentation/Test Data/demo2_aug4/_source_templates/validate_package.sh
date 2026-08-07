#!/usr/bin/env bash
set -euo pipefail

template_dir="$(cd "$(dirname "$0")" && pwd)"
package_dir="$(cd "$template_dir/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

files=(
  "01_Minime_Contracting_Company_Invoice.pdf"
  "02_Health_Safety_Remediation_Photo_Report.pdf"
  "03_ESP_Health_Safety_Preapproval.pdf"
  "04_Natural_Gas_Furnace_Removal_Inspection.pdf"
  "05_Bryant_AHRI_Product_Submittal.pdf"
  "06_Heat_Load_and_Commissioning_Report.pdf"
  "07_BC_Hydro_Service_Confirmation.pdf"
)

for file in "${files[@]}"; do
  test -s "$package_dir/$file"
  pdftotext "$package_dir/$file" "$work_dir/$file.txt"
done

assert_text() {
  local file="$1"
  local text="$2"
  grep -Fq "$text" "$work_dir/$file.txt"
}

assert_text "01_Minime_Contracting_Company_Invoice.pdf" "MiniMe Contracting Company"
assert_text "01_Minime_Contracting_Company_Invoice.pdf" "Mini Home Energy Solutions"
assert_text "01_Minime_Contracting_Company_Invoice.pdf" "ESP1-DEMO0730"
assert_text "01_Minime_Contracting_Company_Invoice.pdf" "203380999"
assert_text "01_Minime_Contracting_Company_Invoice.pdf" "Customer amount due after rebates"
assert_text "01_Minime_Contracting_Company_Invoice.pdf" '$1,924.50'
assert_text "02_Health_Safety_Remediation_Photo_Report.pdf" "BEFORE - July 7, 2026"
assert_text "02_Health_Safety_Remediation_Photo_Report.pdf" "AFTER VIEW A - July 22, 2026"
assert_text "03_ESP_Health_Safety_Preapproval.pdf" "HSR-2026-4187"
assert_text "04_Natural_Gas_Furnace_Removal_Inspection.pdf" "PH-MECH-26-0714"
assert_text "05_Bryant_AHRI_Product_Submittal.pdf" "203380999"
assert_text "05_Bryant_AHRI_Product_Submittal.pdf" "38MAQB18R--3"
assert_text "06_Heat_Load_and_Commissioning_Report.pdf" "12,820"
assert_text "07_BC_Hydro_Service_Confirmation.pdf" "BC Hydro"
assert_text "07_BC_Hydro_Service_Confirmation.pdf" "north of and including the District of 100 Mile House"

printf 'Validated %s upload PDFs successfully.\n' "${#files[@]}"

