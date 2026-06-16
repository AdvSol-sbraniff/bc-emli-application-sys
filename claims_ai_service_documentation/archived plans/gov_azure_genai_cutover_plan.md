# Gov Azure Claims AI Cutover Plan

Status: dev cutover completed

Latest status: Gold dev GenAI, Document Intelligence, and blob storage cutover completed and full invoice package test succeeded. The live `hesp-claims-ai` pod uses Government Azure endpoints with pod-level `hostAliases` workarounds.

Purpose: move the Gold/OpenShift Claims AI service from mixed personal/Advanced Solutions Azure dependencies to Government of BC Azure services, then decide whether to add a local-development relay through Gold.

## 1. Current Understanding

The Claims AI service currently has three Azure dependency areas:

- Document Intelligence now uses the Government Azure Document Intelligence resource in Gold dev.
- Blob storage now uses the Government Azure storage account/container in Gold dev.
- Gold/OpenShift `hesp-claims-ai` now uses the Government Azure OpenAI endpoint.
- Government Azure OpenAI, Document Intelligence, and blob storage have all been tested successfully from Gold using private endpoint IP host aliases.

The current Government Azure OpenAI resource is:

```text
Azure OpenAI account: aoai-esp-dev
Resource group: rg-energy-savings-program-dev
Endpoint: https://aoai-esp-dev.openai.azure.com/
App base URL: https://aoai-esp-dev.openai.azure.com/openai/v1/
Private endpoint: pe-aoai-esp-dev
Private endpoint IP: 10.46.78.4
Deployment: gpt-5-4-chat
Model: gpt-5.4
Model capacity: 100
Rate limit after capacity change: 100,000 tokens/minute and 1,000 requests/minute
Public network access: disabled
```

The current Government Azure Document Intelligence resource is:

```text
Document Intelligence account: docintel-esp-dev
Resource group: rg-energy-savings-program-dev
Endpoint: https://docintel-esp-dev.cognitiveservices.azure.com/
Private endpoint: pe-docintel-esp-dev
Private endpoint IP: 10.46.78.6
Public network access: disabled
```

The current Government Azure blob storage resource is:

```text
Storage account: cbdb71espclaimsdev
Resource group: rg-energy-savings-program-dev
Blob endpoint: https://cbdb71espclaimsdev.blob.core.windows.net/
Container: inv-pdfs-dev
Private endpoint: pe-st-claims-dev-blob
Private endpoint IP: 10.46.78.5
Public network access: disabled
```

Gold/OpenShift can route to `10.46.78.4`, `10.46.78.5`, and `10.46.78.6`. The current workaround is DNS: the pod maps each public service hostname to its private endpoint IP through `hostAliases`.

## 2. Confirmed Test Results

From the Gold `hesp-claims-ai` pod:

```text
Normal DNS + gov key:
403 Public access is disabled.

Forced private endpoint IP 10.46.78.4 + gov key:
200 success

Forced private endpoint IP 10.46.78.4 + actual LLM call:
200 success, response_text = gov azure ok

After Gold dev cutover:
live pod env GENAI_BASE_URL = https://aoai-esp-dev.openai.azure.com/openai/v1/
live pod env GENAI_DEPLOYMENT = gpt-5-4-chat
live pod /etc/hosts maps aoai-esp-dev.openai.azure.com to 10.46.78.4
live pod GenAI smoke test = 200 success, response_text = gold gov app env ok

After full gov Azure cutover:
live pod env DOCINTEL_ENDPOINT = https://docintel-esp-dev.cognitiveservices.azure.com/
live pod env AZURE_BLOB_CONTAINER = inv-pdfs-dev
live pod /etc/hosts maps docintel-esp-dev.cognitiveservices.azure.com to 10.46.78.6
live pod /etc/hosts maps cbdb71espclaimsdev.blob.core.windows.net to 10.46.78.5
live gov blob smoke test = success
live gov DI smoke test = 200 success
live gov GenAI smoke test = 200 success

Full invoice package test:
ingest_run_id = 8894ec46-ea08-4472-b9a5-a547b72a02f7
invoice_id = 716e924c-73eb-485e-9767-7649d2ef630c
invoice_version_id = 09cfa241-3042-42a0-a3c6-d14b072d3ab6
ingest run status = succeeded
invoice status = genai_complete
invoice version result = fail
all 12 pipeline step rows = succeeded
line items = 12
invoice located fields = 50
rulechecks = 34
invoice-version upgrade-type rows = 5
saved GenAI context windows = 4
```

From the local laptop:

```text
Normal DNS + gov key:
403 Public access is disabled.

Forced private endpoint IP 10.46.78.4 + gov key:
timeout / socket hang up
```

Interpretation:

- Gold has the private network path to the Azure private endpoint.
- The local laptop does not currently have a route to the Azure private endpoint, even with the corporate VPN tested during troubleshooting.
- A DNS-only fix is enough for Gold.
- A DNS-only fix is not enough for local laptop development unless the laptop also gets a private route to `10.46.78.4`.

## 3. Overall Cutover Order

Recommended order:

1. Cut Gold dev GenAI over to Government Azure OpenAI. Completed.
2. Cut Gold dev Document Intelligence over to Government Azure Document Intelligence. Completed.
3. Cut Gold dev blob storage over to Government Azure Storage. Completed.
4. Run a full invoice package test using gov GenAI, gov Document Intelligence, and gov blob storage together. Completed.
5. Decide whether local development needs a Gold-hosted relay or can continue using non-gov dev dependencies.

GenAI is first because the Government Azure OpenAI resource already exists and has been proven reachable from Gold when DNS is overridden.

Document Intelligence and blob storage have now been moved for Gold dev. A key implementation note: Document Intelligence cannot fetch a private-only blob SAS URL unless the DI service itself has a valid network path to storage. The app now downloads the private blob from Gold and sends the PDF bytes directly to Document Intelligence for OCR, which avoids that service-to-service private-storage problem.

## 4. Phase 1: Cut Gold Dev GenAI Over To Gov Azure OpenAI

Goal: make the deployed Gold `hesp-claims-ai` service use Government Azure OpenAI instead of the Advanced Solutions GenAI endpoint.

### 4.1 Capture the current Gold configuration

Before changing anything, record the live non-secret GenAI values from the running Gold pod:

```text
GENAI_BASE_URL
GENAI_DEPLOYMENT
GENAI_API_STYLE
DOCINTEL_ENDPOINT
AZURE_BLOB_CONTAINER
```

Do not print or store secret values such as:

```text
GENAI_KEY
DOCINTEL_KEY
AZURE_STORAGE_CONNECTION_STRING
```

Expected current GenAI state before cutover:

```text
GENAI_BASE_URL=https://sbx-ai-foundry-prototype.services.ai.azure.com/api/projects/proj-default/openai/v1/
GENAI_DEPLOYMENT=gpt-5.4
GENAI_API_STYLE=responses
```

### 4.2 Preserve the old Advanced Solutions endpoint value

Kubernetes/OpenShift secrets do not support "commenting out" old values in place.

Instead, record the old Advanced Solutions values in this plan or a deployment note before replacing them:

```text
Old GENAI_BASE_URL: https://sbx-ai-foundry-prototype.services.ai.azure.com/api/projects/proj-default/openai/v1/
Old GENAI_DEPLOYMENT: gpt-5.4
Old GENAI_API_STYLE: responses
```

The proof of cutover will be the restarted pod environment and successful gov Azure GenAI call, not a commented-out secret entry.

### 4.3 Apply the temporary Gold DNS workaround

Until central DNS conditional forwarding is complete, add a pod-level hosts override for `hesp-claims-ai`:

```yaml
hostAliases:
  - ip: '10.46.78.4'
    hostnames:
      - 'aoai-esp-dev.openai.azure.com'
```

This has already been prepared locally in Helm:

- `helm/_claims-ai/templates/deployment.yaml`
- `helm/_claims-ai/values.yaml`
- `helm/main/values-ce8baa-dev.yaml`

The rendered pod spec should include:

```text
hostAliases:
  - hostnames:
    - aoai-esp-dev.openai.azure.com
    ip: 10.46.78.4
```

This workaround should be removed after central DNS correctly resolves:

```text
aoai-esp-dev.openai.azure.com
-> aoai-esp-dev.privatelink.openai.azure.com
-> 10.46.78.4
```

### 4.4 Update the Gold secret/configuration

Update the OpenShift secret/config used by `hesp-claims-ai`.

Target values:

```text
GENAI_BASE_URL=https://aoai-esp-dev.openai.azure.com/openai/v1/
GENAI_DEPLOYMENT=gpt-5-4-chat
GENAI_API_STYLE=responses
GENAI_KEY=<gov Azure OpenAI key>
```

Do not change local `claims_ai_service/.env` as part of this step. Gold does not read the local `.env` file.

Gold currently receives secret-backed environment variables through:

```text
envFrom:
  secretRef:
    name: hesp
```

### 4.5 Restart the Gold Claims AI pod

After updating Helm/secret values, roll the deployment:

```bash
oc -n ce8baa-dev rollout restart deploy/hesp-claims-ai
oc -n ce8baa-dev rollout status deploy/hesp-claims-ai
```

This ensures the container reloads the new environment variables.

### 4.6 Verify the restarted pod

Verify non-secret env values inside the new pod:

```text
GENAI_BASE_URL=https://aoai-esp-dev.openai.azure.com/openai/v1/
GENAI_DEPLOYMENT=gpt-5-4-chat
GENAI_API_STYLE=responses
```

Verify the hosts override:

```bash
cat /etc/hosts
getent hosts aoai-esp-dev.openai.azure.com
```

Expected result:

```text
10.46.78.4 aoai-esp-dev.openai.azure.com
```

### 4.7 Run a direct pod smoke test

From the restarted Gold pod, call the gov Azure OpenAI Responses API through the same endpoint and deployment the app will use.

Expected result:

```text
status=200
response_text=<short expected test response>
```

This proves:

- The pod resolves the gov endpoint correctly.
- The pod can route to the private endpoint.
- The gov key works.
- The deployment `gpt-5-4-chat` works.

### 4.8 Run an application-level smoke test

Run a real Claims AI GenAI action through the deployed app, not just a raw Node/Azure test.

Useful candidates:

- A small known invoice package.
- A GenAI-only rerun against an existing invoice version.
- A minimal endpoint/job path that invokes the Claims AI GenAI client.

Verify:

- The GenAI step succeeds.
- No logs show the old Advanced Solutions endpoint.
- The new pod environment shows the gov endpoint.
- `claims.ingest_step_runs` records expected GenAI output.

## 5. Phase 2: Cut Gold Dev Document Intelligence Over To Gov Azure

Goal: move OCR/Document Intelligence calls from Stephen's personal Azure DI resource to a Government Azure Document Intelligence resource.

### 5.1 Identify or create the gov Document Intelligence resource

Current local/Gold variable shape:

```text
DOCINTEL_ENDPOINT=https://braniff-di.cognitiveservices.azure.com/
DOCINTEL_KEY=<personal DI key>
```

Target gov variable shape:

```text
DOCINTEL_ENDPOINT=<gov Document Intelligence endpoint>
DOCINTEL_KEY=<gov Document Intelligence key>
```

Questions to resolve before cutover:

- Does a gov Document Intelligence resource already exist?
- What is its endpoint hostname?
- Is public network access disabled?
- Does it have a private endpoint?
- What is the private endpoint IP?
- Does Gold already route to that private endpoint?
- Does DNS need a `hostAliases` workaround like Azure OpenAI?

### 5.2 Test gov Document Intelligence from Gold

Before changing the app secret, test from a Gold pod using a harmless DI API call and the gov DI key.

The test should prove:

- DNS resolves correctly, or the hosts override works.
- Gold can route to the gov DI private endpoint.
- The key is valid.
- The resource supports the required Document Intelligence operations used by the claims AI service.

Do not switch the app until this is proven.

### 5.3 Update Gold secret/configuration for DI

After gov DI is tested, update the OpenShift secret/config used by `hesp-claims-ai`:

```text
DOCINTEL_ENDPOINT=<gov Document Intelligence endpoint>
DOCINTEL_KEY=<gov Document Intelligence key>
```

Restart `hesp-claims-ai` and any worker pod that reads these values.

### 5.4 Run OCR smoke tests

Run a small OCR test package and verify:

- Upload/staging still works.
- `ocr_read` succeeds for staged documents.
- `ocr_invoice` succeeds for the resolved invoice.
- `claims.ingest_step_runs.di_results_json` is populated.
- `claims.invoice_versions.di_raw_json` is populated.
- `claims.lineitems` are populated where expected.

## 6. Phase 3: Cut Gold Dev Blob Storage Over To Gov Azure

Goal: move uploaded/staged PDF storage from Stephen's personal Azure storage account/container to a Government Azure storage account/container.

### 6.1 Identify or create the gov storage target

Current local/Gold variable shape:

```text
AZURE_STORAGE_CONNECTION_STRING=<personal storage connection string>
AZURE_BLOB_CONTAINER=inv-pdfs-dev
```

Target gov variable shape:

```text
AZURE_STORAGE_CONNECTION_STRING=<gov storage connection string or approved auth equivalent>
AZURE_BLOB_CONTAINER=<gov claims AI PDF container>
```

Questions to resolve before cutover:

- Does a gov storage account already exist for claims AI PDFs?
- What is the container name?
- Is public network access disabled?
- Does the storage account have a private endpoint for blob service?
- What is the private endpoint IP?
- Does Gold already route to that private endpoint?
- Does DNS need a `hostAliases` workaround?
- Are existing personal-storage PDFs being migrated, or is this cutover only for new uploads?
- If PDFs are migrated, do existing `storage_key` values stay valid?

### 6.2 Decide migration strategy

There are two practical strategies.

New-data-only cutover:

- New uploads go to gov storage.
- Existing test/dev PDFs remain in personal storage until no longer needed.
- Lowest risk for dev if historical records are not important.

Data migration cutover:

- Copy existing blobs from personal storage to gov storage.
- Preserve container-relative `storage_key` values if possible.
- Update only the connection string/container target.
- Higher confidence for existing invoice records, but requires careful copy verification.

The schema stores `storage_key`, not a full URL. If the same key exists in the new gov container, existing database rows can continue to resolve without changing the database.

### 6.3 Test gov blob storage from Gold

Before changing the app secret, test from Gold:

- Write a tiny test blob.
- Read it back.
- Delete it if appropriate.
- Generate or request whatever short-lived URL pattern the app uses for PDF viewing.

This proves the storage account, key/auth, container, DNS, and network path work.

### 6.4 Update Gold secret/configuration for storage

After storage is tested, update:

```text
AZURE_STORAGE_CONNECTION_STRING=<gov value>
AZURE_BLOB_CONTAINER=<gov container>
```

Restart `hesp-claims-ai` and app/worker components that upload or read PDFs.

### 6.5 Run storage smoke tests

Run an invoice package upload and verify:

- The PDF uploads into gov storage.
- The stored `storage_key` is correct.
- The app can read the PDF back.
- Document Intelligence can access the PDF or file bytes as required by the pipeline.
- The PDF viewer/admin screen can load the document.

## 7. Phase 4: Full End-To-End Gold Test

Goal: prove all gov Azure dependencies work together.

Run a known invoice package through Gold after GenAI, DI, and blob storage have been cut over.

Verify:

- Upload creates blobs in gov storage.
- `ocr_read` and `ocr_invoice` use gov Document Intelligence and succeed.
- GenAI calls use gov Azure OpenAI and succeed.
- Product lookup/code rules still run.
- `aggregate_advice` succeeds.
- Invoice status reaches `genai_complete` unless business validation produces warnings/failures.
- Logs and pod environment no longer reference the Advanced Solutions GenAI endpoint or personal DI/blob endpoints.

Completed dev test:

```text
Test file: Test Data/Heat Pump/test007/Invoice 1 - Heat Pump and Electric Service Upgrade.pdf
ingest_run_id: 8894ec46-ea08-4472-b9a5-a547b72a02f7
result: succeeded
invoice status: genai_complete
```

Important capacity lesson:

```text
Model capacity 10 produced repeated Azure OpenAI 429 responses during the triage classifier.
Model capacity 100 succeeded for the full package run.
```

This was not a DNS, private endpoint, DI, or blob storage failure. The real classifier prompt includes OCR/document context, so the deployment needs enough tokens-per-minute capacity for document-sized requests.

## 8. Phase 5: Optional Local Development Through Gold

Goal: allow the local Docker app to use gov Azure OpenAI without giving the laptop broad direct routing to the Azure private endpoint.

This is optional. Local development can continue using the Advanced Solutions GenAI endpoint unless gov parity is required locally.

### 8.1 Why local cannot call gov Azure directly today

The local laptop currently cannot route to:

```text
10.46.78.4
```

Even if local DNS or a hosts-file entry maps:

```text
aoai-esp-dev.openai.azure.com -> 10.46.78.4
```

the call still times out because the laptop does not have a private network route to that address.

This is different from Gold. Gold has the route; it only needs DNS corrected.

### 8.2 Local development options

Option A: Keep local Docker on Advanced Solutions GenAI.

This is the simplest local workflow and avoids adding dev-only networking components.

Option B: Platform-supported VPN route.

The developer laptop VPN would need to route to the Azure private endpoint subnet or host:

```text
10.46.78.4/32
```

or the relevant Azure VNet/private endpoint range.

This requires platform/network approval. The tested corporate VPN did not provide this route.

Option C: Dev-only relay through Gold.

Run a small relay/proxy pod in Gold and use `oc port-forward` from the laptop:

```text
local Docker app
-> localhost port
-> oc port-forward
-> dev-only relay pod in ce8baa-dev
-> aoai-esp-dev.openai.azure.com
-> 10.46.78.4
-> gov Azure OpenAI
```

This is logically similar to a very narrow jumpbox. It is more controlled than broad laptop routing because access depends on OpenShift authentication and the relay can be scoped to Azure OpenAI only.

### 8.3 Relay design choice

Preferred relay design:

- A tiny dev-only pod/deployment in `ce8baa-dev`.
- No public OpenShift route.
- Access only through `oc port-forward`.
- Same `hostAliases` entry for `aoai-esp-dev.openai.azure.com`.
- Forwards only to `https://aoai-esp-dev.openai.azure.com/openai/v1/`.
- Uses the gov Azure key from an OpenShift secret, or forwards the caller's `api-key` header depending on the chosen security model.

Most secure local-dev model:

```text
local app sends request without storing gov key locally
relay injects gov key from Gold secret
relay forwards to gov Azure OpenAI
```

Simplest local-dev model:

```text
local app stores gov key in local .env
relay forwards request as-is
```

The secure model is preferred if the relay is built intentionally.

### 8.4 Local `.env` shape if a relay is used

If a relay exposes a local forwarded port, local `.env` could use a local base URL:

```text
GENAI_BASE_URL=http://localhost:<forwarded-port>/openai/v1/
GENAI_DEPLOYMENT=gpt-5-4-chat
GENAI_API_STYLE=responses
```

Whether `GENAI_KEY` remains local depends on the relay design.

If the relay injects the key, the local app may not need the gov key. If the relay forwards requests as-is, local `.env` still needs `GENAI_KEY`.

### 8.5 Port-forward command shape

Example shape after a relay deployment exists:

```bash
oc -n ce8baa-dev port-forward deploy/aoai-relay 8123:8123
```

Then local app calls:

```text
http://localhost:8123/openai/v1/
```

The relay calls:

```text
https://aoai-esp-dev.openai.azure.com/openai/v1/
```

from inside Gold.

## 9. Open Questions

- Should Gold dev be switched to gov Azure immediately now that the host-alias workaround has been proven?
- What are the gov target resources for Document Intelligence and blob storage?
- Should DI and blob storage be cut over before or after GenAI?
- Do gov DI and gov storage require private endpoints and `hostAliases` workarounds?
- Are existing blobs being migrated or only new uploads?
- Should local Docker continue using Advanced Solutions GenAI for day-to-day development?
- If local gov parity is required, does platform prefer a VPN route or a Gold-hosted relay?
- Should the relay inject the gov key from Gold, or should the local app continue to send the key?
- What is the expected timeline for central DNS conditional forwarders?
- Once central DNS is fixed, who owns removing the temporary `hostAliases` workaround?

## 10. Recommended Next Steps

1. Cut Gold dev over to gov Azure OpenAI first.
2. Identify/create gov Document Intelligence and gov blob storage resources.
3. Verify each gov dependency from Gold before switching the app to it.
4. Cut over DI and blob storage after their private connectivity is proven.
5. Run a full invoice package test using gov GenAI, gov DI, and gov storage together.
6. Keep local Docker on Advanced Solutions/personal Azure dependencies temporarily unless gov parity is required.
7. Ask platform to confirm the supported local-dev pattern:

```text
A. VPN route to Azure private endpoint
B. Gold relay via oc port-forward
C. Local dev does not call gov Azure; integration testing happens in Gold
```

8. Only build the Gold relay if local gov parity is required and platform is comfortable with the pattern.
