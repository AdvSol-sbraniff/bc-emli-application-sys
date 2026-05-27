targetScope = 'subscription'

@description('Resource group where the Azure OpenAI account will be created.')
param serviceResourceGroupName string

@description('Resource group containing the VNet used for private endpoint networking.')
param networkingResourceGroupName string

@description('Azure region for the Azure OpenAI account.')
param openAiLocation string

@description('Azure region for private endpoint and networking resources.')
param networkingLocation string

@description('Globally unique Azure OpenAI account name.')
param openAiAccountName string

@description('Existing VNet name for the private endpoint subnet.')
param vnetName string

@description('Subnet to create for private endpoints.')
param subnetName string

@description('Subnet CIDR inside the existing VNet address space.')
param subnetAddressPrefix string

@description('Network Security Group to attach to the private endpoint subnet.')
param nsgName string

@description('Private endpoint resource name.')
param privateEndpointName string

@description('Private DNS zone used by Azure OpenAI private endpoints.')
param privateDnsZoneName string = 'privatelink.openai.azure.com'

@description('Create a private DNS zone in the networking resource group. Usually false in BC Gov landing zones because private DNS is centrally managed.')
param createPrivateDnsZone bool = false

@description('Existing central private DNS zone resource id to attach to the private endpoint. Leave blank if the central zone is not available yet.')
param existingPrivateDnsZoneId string = ''

@description('Set to true only after confirming the model/version/sku are available in the target region.')
param createModelDeployment bool = false

@description('Azure OpenAI deployment name expected by the app GENAI_DEPLOYMENT value.')
param modelDeploymentName string = 'gpt-5-2-chat'

@description('Azure OpenAI model name. Confirm exact regional availability before enabling createModelDeployment.')
param modelName string = 'gpt-5.2-chat'

@description('Azure OpenAI model version. Leave blank only if Azure accepts the default for the selected model.')
param modelVersion string = ''

@description('Azure OpenAI deployment SKU name.')
param modelSkuName string = 'GlobalStandard'

@description('Azure OpenAI deployment capacity.')
param modelCapacity int = 1

resource serviceRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  name: serviceResourceGroupName
}

resource networkingRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  name: networkingResourceGroupName
}

module openAi 'modules/azure-openai.bicep' = {
  name: 'openai-${uniqueString(deployment().name, openAiAccountName)}'
  scope: serviceRg
  params: {
    accountName: openAiAccountName
    location: openAiLocation
  }
}

module subnet 'modules/subnet-nsg.bicep' = {
  name: 'subnet-nsg-${uniqueString(deployment().name, subnetName)}'
  scope: networkingRg
  params: {
    location: networkingLocation
    vnetName: vnetName
    subnetName: subnetName
    subnetAddressPrefix: subnetAddressPrefix
    nsgName: nsgName
  }
}

module privateDns 'modules/private-dns.bicep' = if (createPrivateDnsZone) {
  name: 'private-dns-${uniqueString(deployment().name, privateDnsZoneName)}'
  scope: networkingRg
  params: {
    privateDnsZoneName: privateDnsZoneName
    vnetName: vnetName
  }
}

var privateDnsZoneId = createPrivateDnsZone ? privateDns!.outputs.privateDnsZoneId : existingPrivateDnsZoneId

module privateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'private-endpoint-${uniqueString(deployment().name, privateEndpointName)}'
  scope: networkingRg
  params: {
    location: networkingLocation
    privateEndpointName: privateEndpointName
    subnetId: subnet.outputs.subnetId
    privateLinkServiceId: openAi.outputs.accountId
    privateDnsZoneId: privateDnsZoneId
  }
}

module modelDeployment 'modules/model-deployment.bicep' = if (createModelDeployment) {
  name: 'model-${uniqueString(deployment().name, modelDeploymentName)}'
  scope: serviceRg
  params: {
    accountName: openAiAccountName
    deploymentName: modelDeploymentName
    modelName: modelName
    modelVersion: modelVersion
    skuName: modelSkuName
    capacity: modelCapacity
  }
  dependsOn: [
    openAi
  ]
}

output openAiAccountId string = openAi.outputs.accountId
output openAiEndpoint string = openAi.outputs.endpoint
output openAiBaseUrlForEnv string = '${openAi.outputs.endpoint}openai/v1/'
output privateEndpointId string = privateEndpoint.outputs.privateEndpointId
output subnetId string = subnet.outputs.subnetId
