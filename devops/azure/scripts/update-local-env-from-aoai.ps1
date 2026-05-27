param(
  [string]$ResourceGroupName = "rg-energy-savings-program-dev",
  [string]$AccountName = "aoai-esp-dev",
  [string]$DeploymentName = "gpt-5-4-chat",
  [string]$EnvPath = "claims_ai_service\.env"
)

$ErrorActionPreference = "Stop"

$az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
if (-not (Test-Path $az)) {
  $az = "az"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$resolvedEnvPath = Join-Path $repoRoot $EnvPath

$endpoint = & $az cognitiveservices account show `
  --resource-group $ResourceGroupName `
  --name $AccountName `
  --query "properties.endpoint" `
  -o tsv

$key = & $az cognitiveservices account keys list `
  --resource-group $ResourceGroupName `
  --name $AccountName `
  --query "key1" `
  -o tsv

if ([string]::IsNullOrWhiteSpace($endpoint)) {
  throw "Azure OpenAI endpoint was blank."
}

if ([string]::IsNullOrWhiteSpace($key)) {
  throw "Azure OpenAI key was blank."
}

$baseUrl = $endpoint.TrimEnd("/") + "/openai/v1/"

if (Test-Path $resolvedEnvPath) {
  $lines = Get-Content $resolvedEnvPath
} else {
  New-Item -ItemType File -Path $resolvedEnvPath -Force | Out-Null
  $lines = @()
}

function Set-EnvLine {
  param(
    [string[]]$Lines,
    [string]$Name,
    [string]$Value
  )

  $replacement = "$Name=$Value"
  $found = $false
  $updated = foreach ($line in $Lines) {
    if ($line -match "^\s*#?\s*$([regex]::Escape($Name))=") {
      $found = $true
      $replacement
    } else {
      $line
    }
  }

  if (-not $found) {
    $updated += $replacement
  }

  return $updated
}

$lines = Set-EnvLine -Lines $lines -Name "GENAI_BASE_URL" -Value $baseUrl
$lines = Set-EnvLine -Lines $lines -Name "GENAI_KEY" -Value $key
$lines = Set-EnvLine -Lines $lines -Name "GENAI_DEPLOYMENT" -Value $DeploymentName
$lines = Set-EnvLine -Lines $lines -Name "GENAI_API_STYLE" -Value "chat_completions"

Set-Content -Path $resolvedEnvPath -Value $lines

Write-Host "Updated local $EnvPath for $AccountName. The key was not printed."
Write-Host "Do not commit .env files."
