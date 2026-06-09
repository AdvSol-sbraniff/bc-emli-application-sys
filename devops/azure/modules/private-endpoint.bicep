targetScope = 'resourceGroup'

@description('Azure region for the private endpoint.')
param location string

@description('Private endpoint name.')
param privateEndpointName string

@description('Subnet resource id for the private endpoint.')
param subnetId string

@description('Resource id of the Azure service that the private endpoint connects to.')
param privateLinkServiceId string

@description('Private Link group ids for the target service, such as account for Cognitive Services/OpenAI or blob for Storage.')
param groupIds array = [
  'account'
]

@description('Private DNS zone id for the target service. Leave blank when DNS is managed elsewhere or hostAliases are used temporarily.')
param privateDnsZoneId string = ''

@description('Name to use for the private DNS zone config when privateDnsZoneId is provided.')
param privateDnsZoneConfigName string = 'default'

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (!empty(privateDnsZoneId)) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneConfigName
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointDnsZoneGroupId string = !empty(privateDnsZoneId) ? dnsZoneGroup.id : ''
