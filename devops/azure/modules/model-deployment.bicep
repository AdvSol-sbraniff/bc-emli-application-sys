targetScope = 'resourceGroup'

@description('Existing Azure OpenAI account name.')
param accountName string

@description('Deployment name used by GENAI_DEPLOYMENT.')
param deploymentName string

@description('Azure OpenAI model name.')
param modelName string

@description('Azure OpenAI model version. Empty string asks Azure to use provider defaults if supported.')
param modelVersion string

@description('Deployment SKU name.')
param skuName string

@description('Deployment capacity.')
param capacity int

resource account 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: accountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: account
  name: deploymentName
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
}

output deploymentId string = deployment.id
