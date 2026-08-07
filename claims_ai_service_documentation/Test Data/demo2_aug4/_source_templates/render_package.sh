#!/usr/bin/env bash
set -euo pipefail

template_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="$(cd "$template_dir/.." && pwd)"

render() {
  local source_file="$1"
  local output_file="$2"

  wkhtmltopdf \
    --quiet \
    --enable-local-file-access \
    --page-size Letter \
    --margin-top 0 \
    --margin-right 0 \
    --margin-bottom 0 \
    --margin-left 0 \
    "$template_dir/$source_file" \
    "$output_dir/$output_file"
}

render "01_invoice.html" "01_Minime_Contracting_Company_Invoice.pdf"
render "02_remediation_photo_report.html" "02_Health_Safety_Remediation_Photo_Report.pdf"
render "03_preapproval.html" "03_ESP_Health_Safety_Preapproval.pdf"
render "04_furnace_removal.html" "04_Natural_Gas_Furnace_Removal_Inspection.pdf"
render "05_ahri_submittal.html" "05_Bryant_AHRI_Product_Submittal.pdf"
render "06_heat_load_commissioning.html" "06_Heat_Load_and_Commissioning_Report.pdf"
render "07_bc_hydro_service.html" "07_BC_Hydro_Service_Confirmation.pdf"
