# Azure OpenAI Infrastructure

This folder contains rerunnable Azure infrastructure for the gov Azure OpenAI path.

The recommended workflow is:

1. Review the parameters in `params/dev.bicepparam`.
2. Run a what-if.
3. Deploy only after the what-if looks right.
4. Store generated keys only in local `.env`, OpenShift secrets, or Key Vault. Never commit keys.

## Login

Run Azure CLI from `C:\` instead of a WSL UNC path:

```powershell
az login --use-device-code
az account set --subscription "55da4745-0ca8-4993-834e-f368541ac85b"
```

## What-If

```powershell
Set-Location C:\
$repo = "\\wsl.localhost\Ubuntu\home\sbraniff\bc-emli-application-sys"
az deployment sub what-if `
  --location canadaeast `
  --template-file "$repo\devops\azure\main.bicep" `
  --parameters "$repo\devops\azure\params\dev.bicepparam"
```

## Deploy

```powershell
Set-Location C:\
$repo = "\\wsl.localhost\Ubuntu\home\sbraniff\bc-emli-application-sys"
az deployment sub create `
  --location canadaeast `
  --template-file "$repo\devops\azure\main.bicep" `
  --parameters "$repo\devops\azure\params\dev.bicepparam"
```

## Update Local `.env`

After deployment, this helper writes the endpoint and API key into `claims_ai_service/.env`.

`claims_ai_service/.env` is intentionally ignored by Git and must not be committed.

```powershell
Set-Location "\\wsl.localhost\Ubuntu\home\sbraniff\bc-emli-application-sys"
.\devops\azure\scripts\update-local-env-from-aoai.ps1
```

The helper sets:

```text
GENAI_BASE_URL
GENAI_KEY
GENAI_DEPLOYMENT
GENAI_API_STYLE
```

## Current Design

The Bicep creates:

- Azure OpenAI account with public network access disabled
- NSG required by BC Gov policy
- private endpoint subnet in `cbdb71-dev-vwan-spoke`
- private endpoint connected to the Azure OpenAI account
- `gpt-5.6-terra` model deployment named `gpt-5.6-terra`

Private DNS is optional in the template because BC Gov policy says private DNS must be created centrally in the connectivity subscription. If the platform team provides the central private DNS zone resource id, set:

```bicep
param existingPrivateDnsZoneId = '/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com'
```

and leave:

```bicep
param createPrivateDnsZone = false
```

## Current Deployment Notes

The account and model currently deployed in dev are:

```text
Account: aoai-esp-dev
Endpoint: https://aoai-esp-dev.openai.azure.com/
Private endpoint IP: 10.46.78.4
Active deployment: gpt-5.6-terra
Model: gpt-5.6-terra
Model version: 2026-07-09
SKU: GlobalStandard
Rollback deployment: gpt-5-4-chat (gpt-5.4, 2026-03-05)
```

`gpt-5.6-terra` was created manually in the Azure portal on 2026-07-13 because BC Gov conditional-access policy prevents this workstation from authenticating Azure CLI. Gold was switched by changing only `GENAI_DEPLOYMENT` in the `hesp` secret. The existing endpoint and account key were retained, and `gpt-5-4-chat` remains available for rollback.

Terra is deployed with `GlobalStandard`. The Azure OpenAI resource is in Canada East, but Global Standard inference may be processed outside Canada and must not be described as Canada-only processing.

The endpoint has public network access disabled. If a caller resolves `aoai-esp-dev.openai.azure.com` to a public IP, data-plane calls fail with:

```text
Public access is disabled. Please configure private endpoint.
```

Gold/OpenShift uses the `claimsAi.hostAliases` entries in `helm/main/values-ce8baa-dev.yaml` to resolve the Azure OpenAI, Document Intelligence, and Blob Storage hostnames to their private endpoint IPs. A live Responses API test from the Gold `hesp-claims-ai` pod succeeded against Terra on 2026-07-13. The desired long-term central private DNS outcome remains:

```text
aoai-esp-dev.openai.azure.com -> aoai-esp-dev.privatelink.openai.azure.com -> 10.46.78.4
```
