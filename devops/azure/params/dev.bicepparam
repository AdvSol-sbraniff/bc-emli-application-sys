using '../main.bicep'

param serviceResourceGroupName = 'rg-energy-savings-program-dev'
param networkingResourceGroupName = 'cbdb71-dev-networking'
param openAiLocation = 'canadaeast'
param docIntelLocation = 'canadacentral'
param storageLocation = 'canadacentral'
param networkingLocation = 'canadacentral'

param openAiAccountName = 'aoai-esp-dev'
param docIntelAccountName = 'docintel-esp-dev'
param storageAccountName = 'cbdb71espclaimsdev'
param storageBlobContainerName = 'inv-pdfs-dev'

param vnetName = 'cbdb71-dev-vwan-spoke'
param subnetName = 'aoai-private-endpoints'
param subnetAddressPrefix = '10.46.78.0/27'
param nsgName = 'nsg-aoai-private-endpoints'
param privateEndpointName = 'pe-aoai-esp-dev'
param docIntelPrivateEndpointName = 'pe-docintel-esp-dev'
param storagePrivateEndpointName = 'pe-st-claims-dev-blob'
param createPrivateDnsZone = false
param existingPrivateDnsZoneId = ''

param createModelDeployment = true
param modelDeploymentName = 'gpt-5.6-terra'
param modelName = 'gpt-5.6-terra'
param modelVersion = '2026-07-09'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 100
