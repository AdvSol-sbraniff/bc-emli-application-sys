targetScope = 'resourceGroup'

@description('Azure OpenAI account name.')
param accountName string

@description('Azure region for the Azure OpenAI account.')
param location string

resource account 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: accountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
    }
  }
}

output accountId string = account.id
output endpoint string = account.properties.endpoint
