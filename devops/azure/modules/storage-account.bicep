targetScope = 'resourceGroup'

@description('Azure Storage account name. Must be globally unique, lowercase, and 3-24 characters.')
param accountName string

@description('Azure region for the Storage account.')
param location string

@description('Blob container used by Claims AI for uploaded PDFs.')
param blobContainerName string

resource account 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: accountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: account
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: blobContainerName
  properties: {
    publicAccess: 'None'
  }
}

output accountId string = account.id
output blobEndpoint string = account.properties.primaryEndpoints.blob
output containerName string = container.name
