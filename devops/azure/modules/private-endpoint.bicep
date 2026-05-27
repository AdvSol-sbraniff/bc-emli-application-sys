targetScope = 'resourceGroup'

@description('Azure region for the private endpoint.')
param location string

@description('Private endpoint name.')
param privateEndpointName string

@description('Subnet resource id for the private endpoint.')
param subnetId string

@description('Azure OpenAI account resource id.')
param privateLinkServiceId string

@description('Private DNS zone id for Azure OpenAI.')
param privateDnsZoneId string = ''

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
          groupIds: [
            'account'
          ]
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
        name: 'openai'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointDnsZoneGroupId string = !empty(privateDnsZoneId) ? dnsZoneGroup.id : ''
