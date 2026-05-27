targetScope = 'resourceGroup'

@description('Private DNS zone name for Azure OpenAI private endpoint records.')
param privateDnsZoneName string

@description('Existing VNet name to link to the private DNS zone.')
param vnetName string

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource zone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: zone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output privateDnsZoneId string = zone.id
output privateDnsVnetLinkId string = vnetLink.id
