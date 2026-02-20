#!/usr/bin/env bash
set -euo pipefail

HOST="host.docker.internal"
PORT="3001"

curl -i -X POST "http://${HOST}:${PORT}/inv/upload-pdf" \
  -F "sessionId=dd8a19be-b43b-4559-87b1-46c6b5f5cfd4" \
  -F "invoiceVersionId=ef86880c-7570-4830-a083-f31301a22118" \
  -F "file=@original.PDF;type=application/pdf"
