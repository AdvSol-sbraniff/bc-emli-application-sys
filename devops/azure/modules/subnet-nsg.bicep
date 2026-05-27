targetScope = 'resourceGroup'

@description('Azure region for the NSG.')
param location string

@description('Existing VNet name.')
param vnetName string

@description('Subnet name to create or update.')
param subnetName string

@description('Subnet CIDR inside the existing VNet address space.')
param subnetAddressPrefix string

@description('Network Security Group name.')
param nsgName string

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: []
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

output nsgId string = nsg.id
output subnetId string = subnet.id
