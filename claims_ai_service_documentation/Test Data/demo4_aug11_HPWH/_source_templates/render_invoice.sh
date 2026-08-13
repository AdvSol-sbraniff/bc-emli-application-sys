#!/usr/bin/env bash
set -euo pipefail

template_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="$(cd "$template_dir/.." && pwd)"

wkhtmltopdf \
  --quiet \
  --enable-local-file-access \
  --page-size Letter \
  --margin-top 0 \
  --margin-right 0 \
  --margin-bottom 0 \
  --margin-left 0 \
  "$template_dir/01_invoice.html" \
  "$output_dir/01_MiniMe_Heat_Pump_Water_Heater_Invoice.pdf"
