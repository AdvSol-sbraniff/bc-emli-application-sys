using '../main.bicep'

param serviceResourceGroupName = 'rg-energy-savings-program-dev'
param networkingResourceGroupName = 'cbdb71-dev-networking'
param openAiLocation = 'canadaeast'
param networkingLocation = 'canadacentral'

param openAiAccountName = 'aoai-esp-dev'

param vnetName = 'cbdb71-dev-vwan-spoke'
param subnetName = 'aoai-private-endpoints'
param subnetAddressPrefix = '10.46.78.0/27'
param nsgName = 'nsg-aoai-private-endpoints'
param privateEndpointName = 'pe-aoai-esp-dev'
param createPrivateDnsZone = false
param existingPrivateDnsZoneId = ''

param createModelDeployment = true
param modelDeploymentName = 'gpt-5-4-chat'
param modelName = 'gpt-5.4'
param modelVersion = '2026-03-05'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 1
