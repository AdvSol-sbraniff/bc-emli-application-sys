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
- `gpt-5.4` model deployment named `gpt-5-4-chat`

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
Deployment: gpt-5-4-chat
Model: gpt-5.4
Model version: 2026-03-05
SKU: GlobalStandard
Capacity: 1
```

`gpt-5.5` was checked first because it was the smartest available model in the Canada regions, but Azure rejected the deployment with insufficient capacity for its required `GlobalProvisionedManaged` SKU. `gpt-5.4` was the best available successful deployment.

The endpoint has public network access disabled. If a caller resolves `aoai-esp-dev.openai.azure.com` to a public IP, data-plane calls fail with:

```text
Public access is disabled. Please configure private endpoint.
```

Gold/OpenShift and local laptop testing both currently resolve the endpoint to a public Azure IP, so the remaining platform task is central private DNS/routing. The desired private DNS outcome is:

```text
aoai-esp-dev.openai.azure.com -> aoai-esp-dev.privatelink.openai.azure.com -> 10.46.78.4
```
