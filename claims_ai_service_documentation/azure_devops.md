# Azure DevOps

Status: post-cutover operating draft

Purpose: explain how Claims AI uses Government Azure and OpenShift Gold after go-live, how the infrastructure is deployed, how the application is configured, and how operators can test or troubleshoot the Azure dependencies without decoding the Bicep or platform networking from scratch.

This is the plain-English companion to:

- `devops/azure/`
- `helm/main/values-ce8baa-dev.yaml`
- OpenShift Gold namespace `ce8baa-dev`
- `claims_ai_service/.env` for local development only
- `claims_ai_service_documentation/gov_azure_genai_cutover_plan.md` for the historical cutover record

## Table Of Contents

1. [Audience And Scope](#1-audience-and-scope)
2. [Post-Go-Live Runtime Model](#2-post-go-live-runtime-model)
3. [Government Azure Resources](#3-government-azure-resources)
4. [OpenShift Gold Runtime](#4-openshift-gold-runtime)
5. [Network And DNS Model](#5-network-and-dns-model)
6. [Application Configuration](#6-application-configuration)
7. [Bicep Infrastructure](#7-bicep-infrastructure)
8. [Deployment And Rollout](#8-deployment-and-rollout)
9. [Testing And Evidence](#9-testing-and-evidence)
10. [Local Development](#10-local-development)
11. [Troubleshooting](#11-troubleshooting)
12. [Operational Rules](#12-operational-rules)
13. [Appendix: Commands And References](#13-appendix-commands-and-references)

## 1. Audience And Scope

### 1.1 Intended readers

This document is for developers, DevOps maintainers, platform support staff, and future project owners who need to understand how Claims AI talks to Azure.

It assumes the reader knows basic OpenShift, Azure, and environment-variable concepts. It does not assume the reader knows why this setup was originally hard.

### 1.2 What this document covers

This document covers the Claims AI Azure dependencies used by the Gold dev deployment:

- Azure OpenAI for GenAI classification and validation.
- Azure Document Intelligence for OCR/read and invoice extraction.
- Azure Blob Storage for uploaded invoice/supporting-document PDFs.
- The OpenShift Gold configuration that points the app to those services.
- The temporary host-alias DNS workaround used until platform DNS resolves private endpoints correctly.
- The Bicep files used to recreate or update the Azure resources.

### 1.3 What this document does not cover

This document does not explain every Claims AI data table, every Rails job, or every validation rule. Those belong in the Claims AI data model and application docs.

This document also does not store secrets. Azure keys, storage connection strings, and OpenShift secret values must never be committed to Git.

### 1.4 Short glossary

DI means Azure Document Intelligence. It is the Azure service used for OCR and invoice/document extraction.

Gold means the BC Gov OpenShift Gold cluster.

Private endpoint means the Azure service has a private IP in the government Azure network. Public network access is disabled.

Host alias means a Kubernetes pod-level `/etc/hosts` entry. In this project it temporarily maps Azure public hostnames to private endpoint IPs.

## 2. Post-Go-Live Runtime Model

### 2.1 Bottom line

Claims AI in Gold dev now uses the same Government Azure dependency pattern expected after go-live:

- GenAI: Government Azure OpenAI.
- OCR: Government Azure Document Intelligence.
- PDF storage: Government Azure Blob Storage.

The full invoice package test succeeded after the cutover. The app is no longer dependent on Stephen's personal DI/blob resources or the Advanced Solutions GenAI endpoint in Gold dev.

### 2.2 Runtime flow

The runtime flow is:

```text
Rails app / Sidekiq claims jobs
  -> hesp-claims-ai Node service
      -> gov Azure Blob Storage
      -> gov Azure Document Intelligence
      -> gov Azure OpenAI
  -> claims database evidence tables
```

Rails and Sidekiq do not call Azure directly for Claims AI document processing. They call the internal Node service at:

```text
INV_NODE_BASE_URL=http://hesp-claims-ai:3001
```

### 2.3 Important implementation detail

The Node service reads private blobs from Gold and sends PDF bytes directly to Document Intelligence.

This matters because private-only Blob Storage cannot be safely handled by giving DI a SAS URL unless the DI service itself has network access to that private blob endpoint. Sending bytes from the Gold pod avoids that service-to-service private-network problem.

Relevant code:

```text
claims_ai_service/src/services/inv.service.ts
runDiAnalyzeFromBytes()
ocrByBlob()
```

The browser must not be sent direct Azure Blob SAS URLs for private-only gov storage. PDF viewing uses a same-origin Rails URL instead. Rails streams the PDF by asking the internal Node service to read the private blob from inside Gold.

```text
Browser
  -> Rails /api/claims/.../pdf
  -> hesp-claims-ai /inv/download-blob
  -> gov Azure Blob private endpoint
```

This keeps the storage account private while still allowing logged-in users to view PDFs through the application.

### 2.4 Known-good full test

The full cutover test used this run:

```text
ingest_run_id: 8894ec46-ea08-4472-b9a5-a547b72a02f7
invoice_id: 716e924c-73eb-485e-9767-7649d2ef630c
invoice_version_id: 09cfa241-3042-42a0-a3c6-d14b072d3ab6
ingest run status: succeeded
invoice status: genai_complete
pipeline steps: all 12 succeeded
```

The invoice's AI result was `fail`, but that was a business validation result for the test invoice, not an infrastructure failure.

## 3. Government Azure Resources

### 3.1 Subscription and resource groups

Current dev subscription:

```text
Subscription name: cbdb71-dev - Savings Program Application AI
Subscription ID: 55da4745-0ca8-4993-834e-f368541ac85b
Tenant: Government of BC
Tenant ID: 6fdb5200-3d0d-4a8a-b036-d3685e359adc
```

Service resource group:

```text
rg-energy-savings-program-dev
```

Networking resource group:

```text
cbdb71-dev-networking
```

### 3.2 Azure OpenAI

```text
Account: aoai-esp-dev
Endpoint: https://aoai-esp-dev.openai.azure.com/
App base URL: https://aoai-esp-dev.openai.azure.com/openai/v1/
Private endpoint: pe-aoai-esp-dev
Private endpoint IP: 10.46.78.4
Deployment: gpt-5-4-chat
Model: gpt-5.4
Model version: 2026-03-05
SKU: GlobalStandard
Capacity: 100
Public network access: disabled
```

The model capacity is important. Capacity `10` caused repeated `429 Too Many Requests` failures on real document-sized classifier prompts. Capacity `100` succeeded for the full invoice package run.

### 3.3 Document Intelligence

```text
Account: docintel-esp-dev
Endpoint: https://docintel-esp-dev.cognitiveservices.azure.com/
Kind: FormRecognizer
Private endpoint: pe-docintel-esp-dev
Private endpoint IP: 10.46.78.6
Public network access: disabled
```

The app environment variable is:

```text
DOCINTEL_ENDPOINT=https://docintel-esp-dev.cognitiveservices.azure.com/
```

### 3.4 Blob Storage

```text
Account: cbdb71espclaimsdev
Blob endpoint: https://cbdb71espclaimsdev.blob.core.windows.net/
Container: inv-pdfs-dev
Private endpoint: pe-st-claims-dev-blob
Private endpoint IP: 10.46.78.5
Public network access: disabled
```

The app environment variable is:

```text
AZURE_BLOB_CONTAINER=inv-pdfs-dev
```

The storage connection string is secret-backed and must not be printed or committed.

## 4. OpenShift Gold Runtime

### 4.1 Namespace

Current Gold dev namespace:

```text
ce8baa-dev
```

### 4.2 Main components

The relevant deployed components are:

- `hesp-app`: Rails web/app pod.
- `hesp-sidekiq-claims`: Sidekiq worker for Claims AI OCR/GenAI jobs.
- `hesp-claims-ai`: Node service that calls Azure Blob, DI, and OpenAI.
- `hesp-crunchydb-ha-*`: PostgreSQL database pod.

### 4.3 Current Node service image

The normal post-cutover image is:

```text
ghcr.io/advsol-sbraniff/hesp-claims-ai:main
```

This image includes:

- Direct PDF-byte submission to Document Intelligence.
- Private blob download support for Rails PDF proxying.
- GenAI retry/backoff handling for Azure throttling.

### 4.4 Helm values

The Gold dev Helm values are in:

```text
helm/main/values-ce8baa-dev.yaml
```

The relevant section is:

```yaml
claimsAi:
  enabled: true
  image:
    repository: ghcr.io/advsol-sbraniff/hesp-claims-ai
    tag: main
    pullPolicy: Always
  hostAliases:
    - ip: '10.46.78.4'
      hostnames:
        - 'aoai-esp-dev.openai.azure.com'
    - ip: '10.46.78.6'
      hostnames:
        - 'docintel-esp-dev.cognitiveservices.azure.com'
    - ip: '10.46.78.5'
      hostnames:
        - 'cbdb71espclaimsdev.blob.core.windows.net'
```

## 5. Network And DNS Model

### 5.1 Why host aliases are currently used

The Azure resources have public network access disabled. They are only reachable through private endpoint IPs.

Gold can route to the private endpoint IPs, but normal DNS may still resolve the public Azure hostname to a public Azure address. If that happens, Azure rejects the call with:

```text
403 Public access is disabled.
```

The current workaround is to force the pod to resolve each Azure hostname to its private endpoint IP through `hostAliases`.

### 5.2 Current host aliases

```text
aoai-esp-dev.openai.azure.com                  -> 10.46.78.4
docintel-esp-dev.cognitiveservices.azure.com   -> 10.46.78.6
cbdb71espclaimsdev.blob.core.windows.net       -> 10.46.78.5
```

### 5.3 Future DNS target

When platform DNS is ready, the host aliases should no longer be necessary. The desired behavior is that normal DNS resolves each service hostname through Azure private-link DNS to its private endpoint IP.

Until that is proven from inside Gold pods, do not remove the host aliases.

### 5.4 Local laptop routing

The local laptop does not automatically have a private route to the Azure private endpoint IPs.

A local hosts-file change alone is not enough. It can make the name resolve to `10.46.78.x`, but the laptop still needs a network route to that private address. During troubleshooting, the local laptop timed out even when the OpenAI hostname was forced to the private endpoint IP.

## 6. Application Configuration

### 6.1 Gold configuration source

Gold does not read `claims_ai_service/.env`.

Gold receives secret-backed environment variables through the OpenShift secret:

```text
secretRef:
  name: hesp
```

### 6.2 Non-secret values to verify

These values are safe to print when troubleshooting:

```text
GENAI_BASE_URL=https://aoai-esp-dev.openai.azure.com/openai/v1/
GENAI_DEPLOYMENT=gpt-5-4-chat
GENAI_API_STYLE=responses
DOCINTEL_ENDPOINT=https://docintel-esp-dev.cognitiveservices.azure.com/
AZURE_BLOB_CONTAINER=inv-pdfs-dev
INV_NODE_BASE_URL=http://hesp-claims-ai:3001
```

### 6.3 Secret values not to print

Do not print, paste into docs, or commit:

```text
GENAI_KEY
DOCINTEL_KEY
AZURE_STORAGE_CONNECTION_STRING
```

### 6.4 Optional GenAI retry knobs

The Node service has defaults for retrying temporary GenAI failures:

```text
GENAI_MAX_ATTEMPTS default: 6
GENAI_RETRY_BASE_MS default: 5000
GENAI_RETRY_MAX_MS default: 60000
```

These can be added as environment variables if operations needs different retry behavior. They are not a substitute for sufficient Azure OpenAI model capacity.

## 7. Bicep Infrastructure

### 7.1 Folder structure

The infrastructure entry point is:

```text
devops/azure/main.bicep
```

Dev parameters are:

```text
devops/azure/params/dev.bicepparam
```

Modules are in:

```text
devops/azure/modules/
```

### 7.2 What Bicep creates

The Bicep currently manages:

- Azure OpenAI account.
- Azure OpenAI model deployment.
- Document Intelligence account.
- Storage account and blob container.
- Private endpoint subnet and NSG.
- Private endpoint for OpenAI.
- Private endpoint for Document Intelligence.
- Private endpoint for Blob Storage.

### 7.3 Current important parameters

```text
openAiAccountName = aoai-esp-dev
docIntelAccountName = docintel-esp-dev
storageAccountName = cbdb71espclaimsdev
storageBlobContainerName = inv-pdfs-dev
modelDeploymentName = gpt-5-4-chat
modelName = gpt-5.4
modelVersion = 2026-03-05
modelSkuName = GlobalStandard
modelCapacity = 100
```

### 7.4 What-if workflow

Run Azure CLI from `C:\` to avoid WSL UNC path problems:

```powershell
Set-Location C:\
$repo = "\\wsl.localhost\Ubuntu\home\sbraniff\bc-emli-application-sys"
az deployment sub what-if `
  --location canadaeast `
  --template-file "$repo\devops\azure\main.bicep" `
  --parameters "$repo\devops\azure\params\dev.bicepparam"
```

### 7.5 Deploy workflow

```powershell
Set-Location C:\
$repo = "\\wsl.localhost\Ubuntu\home\sbraniff\bc-emli-application-sys"
az deployment sub create `
  --location canadaeast `
  --template-file "$repo\devops\azure\main.bicep" `
  --parameters "$repo\devops\azure\params\dev.bicepparam"
```

Use `canadaeast` for the subscription deployment location because the existing deployment record named `main` was created there.

### 7.6 Updating model capacity directly

If only the model deployment capacity must be changed, this command can upsert the deployment:

```powershell
az cognitiveservices account deployment create `
  --resource-group rg-energy-savings-program-dev `
  --name aoai-esp-dev `
  --deployment-name gpt-5-4-chat `
  --model-name gpt-5.4 `
  --model-version 2026-03-05 `
  --model-format OpenAI `
  --sku-name GlobalStandard `
  --sku-capacity 100
```

Keep `devops/azure/params/dev.bicepparam` in sync after any direct Azure CLI change.

## 8. Deployment And Rollout

### 8.1 Build and push Claims AI image

Run from WSL/repo root:

```bash
docker build -f devops/docker/claims-ai/Dockerfile \
  -t ghcr.io/advsol-sbraniff/hesp-claims-ai:<tag> .

docker push ghcr.io/advsol-sbraniff/hesp-claims-ai:<tag>
```

Use `main` for the normal Gold dev flow:

```text
main
```

Temporary descriptive tags are still useful for one-off cutover testing, but remember to move Gold and Helm back to `main` after the image is proven.

If a change touches Rails routes/controllers/frontend, rebuild `hesp-app:main`. If a change touches `claims_ai_service`, rebuild `hesp-claims-ai:main`. The PDF proxy path touches both: Rails owns the browser-facing `/api/claims/.../pdf` route, and Node owns `/inv/download-blob`.

### 8.1.1 Build and push Rails app image

```bash
docker build -f devops/docker/app/Dockerfile \
  -t ghcr.io/advsol-sbraniff/hesp-app:main .

docker push ghcr.io/advsol-sbraniff/hesp-app:main
```

Restart the app-family deployments:

```bash
oc -n ce8baa-dev rollout restart \
  deploy/hesp-app \
  deploy/hesp-sidekiq \
  deploy/hesp-sidekiq-claims \
  deploy/hesp-anycable-rpc
```

### 8.1.2 Build and push Claims AI Node image

```bash
docker build -f devops/docker/claims-ai/Dockerfile \
  -t ghcr.io/advsol-sbraniff/hesp-claims-ai:main .

docker push ghcr.io/advsol-sbraniff/hesp-claims-ai:main
```

Restart the Node deployment:

```bash
oc -n ce8baa-dev rollout restart deploy/hesp-claims-ai
```

### 8.2 Update live deployment

```bash
oc -n ce8baa-dev set image deploy/hesp-claims-ai \
  claimsai=ghcr.io/advsol-sbraniff/hesp-claims-ai:<tag>

oc -n ce8baa-dev rollout status deploy/hesp-claims-ai --timeout=180s
```

### 8.3 Update Helm values

After changing the live image, update:

```text
helm/main/values-ce8baa-dev.yaml
```

The live deployment and Helm values should not drift for long.

### 8.4 Restart after secret changes

If `hesp` secret values are changed, restart the pods that read them:

```bash
oc -n ce8baa-dev rollout restart deploy/hesp-claims-ai
oc -n ce8baa-dev rollout restart deploy/hesp-app
oc -n ce8baa-dev rollout restart deploy/hesp-sidekiq-claims
```

At minimum, restart `hesp-claims-ai` for Azure endpoint/key changes.

## 9. Testing And Evidence

### 9.1 Fast environment check

```bash
oc -n ce8baa-dev exec deploy/hesp-claims-ai -c claimsai -- \
  printenv GENAI_BASE_URL GENAI_DEPLOYMENT GENAI_API_STYLE DOCINTEL_ENDPOINT AZURE_BLOB_CONTAINER
```

Expected:

```text
https://aoai-esp-dev.openai.azure.com/openai/v1/
gpt-5-4-chat
responses
https://docintel-esp-dev.cognitiveservices.azure.com/
inv-pdfs-dev
```

### 9.2 Host alias check

```bash
oc -n ce8baa-dev get deploy hesp-claims-ai \
  -o jsonpath='{.spec.template.spec.hostAliases}'
```

Expected hostnames:

```text
aoai-esp-dev.openai.azure.com
docintel-esp-dev.cognitiveservices.azure.com
cbdb71espclaimsdev.blob.core.windows.net
```

### 9.3 Full invoice package test

A valid full test should prove:

- Blob upload succeeds.
- Show PDF uses an app URL, not a direct `blob.core.windows.net` URL.
- OCR read succeeds.
- Triage classifier succeeds.
- Invoice OCR succeeds.
- GenAI common and upgrade calls succeed.
- Product lookup succeeds.
- Code rules succeed.
- Aggregate advice succeeds.
- Invoice reaches `genai_complete`.

The known-good cutover test had these step rows:

```text
upload_package_stage      succeeded
ocr_read                  succeeded
triage_classifier         succeeded
ocr_invoice               succeeded
case_facts                succeeded
genai_common              succeeded
genai_upgrade             succeeded
genai_upgrade             succeeded
product_lookup_enrichment succeeded
code_common               succeeded
code_upgrade              succeeded
aggregate_advice          succeeded
```

### 9.4 Evidence to record

After a test, record:

- `ingest_run_id`
- `invoice_id`
- `invoice_version_id`
- `claims.ingest_runs.status`
- `claims.invoices.status`
- Step status summary from `claims.ingest_step_runs`
- Counts for line items, located fields, rulechecks, upgrade-type rows, and context windows

## 10. Local Development

### 10.1 Local `.env`

`claims_ai_service/.env` is for local Docker development only. It is ignored by Git and should never be treated as the Gold source of truth.

### 10.2 Local gov Azure access

Local Docker does not automatically reach the Government Azure private endpoints.

The laptop needs both:

- DNS resolving the Azure hostname to the private endpoint IP.
- A network route to that private endpoint IP.

The hosts-file trick only solves the first item. It does not create the route.

### 10.3 Practical local options

The practical local choices are:

- Keep local Docker using non-gov dev dependencies when exact gov parity is not required.
- Ask platform/network teams for an approved VPN/private route to the Azure private endpoint range.
- Build a narrow dev-only relay through Gold and access it with `oc port-forward`.

The Gold relay pattern is logically a narrow jumpbox. It should be treated as an explicit dev tool, not an accidental production dependency.

## 11. Troubleshooting

### 11.1 `403 Public access is disabled`

Meaning: the caller reached the public Azure path for a private-only resource.

Check:

- Does the pod have the correct host alias?
- Does DNS inside the pod resolve to the private endpoint IP?
- Is the endpoint hostname correct?

### 11.2 Timeout to `10.46.78.x`

Meaning: the caller may have the right private IP but no route to it.

This is expected from a normal laptop. It should not happen from Gold for the known private endpoint IPs.

### 11.3 `429 Too Many Requests`

Meaning: Azure OpenAI throttled the request.

For Claims AI, this can happen if model capacity is too low for document-sized prompts. Capacity `10` failed during cutover. Capacity `100` succeeded.

Check:

```powershell
az cognitiveservices account deployment show `
  --resource-group rg-energy-savings-program-dev `
  --name aoai-esp-dev `
  --deployment-name gpt-5-4-chat `
  --query "{sku:sku,rateLimits:properties.rateLimits}"
```

### 11.4 DI cannot download blob URL

Meaning: Document Intelligence was probably given a URL to a private-only blob that DI cannot fetch.

Expected fix: the app should download the blob in the Gold pod and send PDF bytes to DI. The current `hesp-claims-ai` image includes this fix.

### 11.5 Browser PDF viewer shows Azure `AuthorizationFailure`

Meaning: the browser was sent a direct Azure Blob SAS URL for a private-only storage account.

The browser is outside the Gold private network path, so direct `blob.core.windows.net` links are not reliable after the gov storage cutover.

Expected fix:

```text
pdf_url endpoint returns /api/claims/.../pdf
Rails streams the PDF through hesp-claims-ai /inv/download-blob
Browser never opens the Azure Blob URL directly
```

### 11.6 Wrong key or endpoint

Symptoms may include `401`, `403`, or generic Node `500` wrappers.

Check non-secret env values first. Then rotate or verify secret-backed values in OpenShift without printing them into logs or docs.

### 11.7 Azure CLI deployment location error

If Azure says deployment `MAIN` already exists in another location, rerun using:

```text
--location canadaeast
```

The subscription deployment location is about the deployment record, not necessarily where every Azure resource lives.

## 12. Operational Rules

### 12.1 Secrets

Never commit:

- Azure keys.
- Storage connection strings.
- `.env` files.
- Full OpenShift secret dumps.

### 12.2 Host aliases

Host aliases are an approved temporary workaround for Gold dev until platform DNS resolves private endpoints correctly from the pod.

Do not remove them until a pod-level test proves normal DNS resolves the same hostnames to the expected private endpoint IPs.

### 12.3 Rollback

Rollback options depend on what changed:

- Bad image: roll back `hesp-claims-ai` image tag.
- Bad secret: restore previous OpenShift secret values and restart pods.
- Bad Azure capacity/model change: upsert the previous model deployment settings.
- Bad Bicep change: review what-if before reapplying.

### 12.4 Post-go-live minimum evidence

After any Azure dependency change, capture:

- Live non-secret env values.
- Host alias or DNS proof.
- Azure deployment capacity/rate limit if OpenAI changed.
- A full invoice package run or a clearly scoped smoke test.

## 13. Appendix: Commands And References

### 13.1 Azure login

```powershell
Set-Location C:\
az login --tenant "6fdb5200-3d0d-4a8a-b036-d3685e359adc" --use-device-code
az account set --subscription "55da4745-0ca8-4993-834e-f368541ac85b"
```

### 13.2 Current Azure resource summary

```text
OpenAI endpoint: https://aoai-esp-dev.openai.azure.com/
OpenAI private IP: 10.46.78.4
DI endpoint: https://docintel-esp-dev.cognitiveservices.azure.com/
DI private IP: 10.46.78.6
Blob endpoint: https://cbdb71espclaimsdev.blob.core.windows.net/
Blob private IP: 10.46.78.5
Blob container: inv-pdfs-dev
```

### 13.3 Useful OpenShift commands

```bash
oc -n ce8baa-dev get pods
oc -n ce8baa-dev logs deploy/hesp-claims-ai -c claimsai --since=30m
oc -n ce8baa-dev rollout status deploy/hesp-claims-ai
oc -n ce8baa-dev get deploy hesp-claims-ai -o yaml
```

### 13.4 Useful files

```text
claims_ai_service/src/services/inv.service.ts
devops/azure/main.bicep
devops/azure/params/dev.bicepparam
devops/docker/claims-ai/Dockerfile
helm/_claims-ai/templates/deployment.yaml
helm/main/values-ce8baa-dev.yaml
claims_ai_service_documentation/gov_azure_genai_cutover_plan.md
```

### 13.5 Open questions

- When will platform DNS make the host aliases unnecessary?
- Should prod use the same OpenAI model capacity, or should it be sized from expected invoice volume?
- Should local development keep using non-gov Azure dependencies, or should a Gold relay be built for gov-parity testing?
- Do historical dev blobs need migration, or is new-data-only gov storage sufficient?
