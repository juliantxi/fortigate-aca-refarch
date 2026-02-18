// ============================================================
// modules/spoke-network.bicep
// Spoke VNet, Container Apps subnet, NSG, UDR
// ============================================================
param location string
param env string
param fortiGateInternalLbIp string

var spokeVnetName = 'vnet-spoke-${env}'
var spokeVnetPrefix = '10.1.0.0/16'
var containerAppsSubnetName = 'snet-container-apps'
var containerAppsSubnetPrefix = '10.1.0.0/23' // minimum /23 for Container Apps
var privateEndpointsSubnetName = 'snet-private-endpoints'
var privateEndpointsSubnetPrefix = '10.1.2.0/24'

// ── NSG for Container Apps subnet ──────────────────────────
// Container Apps with internal ingress requires minimal NSG rules.
// Azure manages most internal traffic automatically.
resource nsgContainerApps 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-container-apps-${env}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-inbound-from-fortigate'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.0.0.0/16' // hub VNet
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['80', '443']
        }
      }
      {
        name: 'allow-aca-internal'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: containerAppsSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: containerAppsSubnetPrefix
          destinationPortRange: '*'
        }
      }
      {
        name: 'deny-all-other-inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource nsgPrivateEndpoints 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-private-endpoints-${env}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-from-container-apps'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: containerAppsSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointsSubnetPrefix
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ── UDR — force traffic through FortiGate ──────────────────
resource udrContainerApps 'Microsoft.Network/routeTables@2023-09-01' = {
  name: 'udr-container-apps-${env}'
  location: location
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'route-default-to-fortigate'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: fortiGateInternalLbIp
        }
      }
      {
        // Keep Azure management traffic local — required for Container Apps control plane
        name: 'route-azure-mgmt'
        properties: {
          addressPrefix: 'AzureCloud'
          nextHopType: 'Internet'
        }
      }
    ]
  }
}

// ── Spoke VNet ─────────────────────────────────────────────
resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: spokeVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [spokeVnetPrefix]
    }
    subnets: [
      {
        name: containerAppsSubnetName
        properties: {
          addressPrefix: containerAppsSubnetPrefix
          networkSecurityGroup: { id: nsgContainerApps.id }
          routeTable: { id: udrContainerApps.id }
          // Container Apps environment delegation
          delegations: [
            {
              name: 'container-apps-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointsSubnetName
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          networkSecurityGroup: { id: nsgPrivateEndpoints.id }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// ── Outputs ────────────────────────────────────────────────
// Note: containerAppsLbIp is assigned by Azure after the Container Apps
// Environment is created. We use a placeholder here; update the private
// DNS A record after deployment using the environment's staticIp output.
output spokeVnetName string = spokeVnet.name
output spokeVnetId string = spokeVnet.id
output containerAppsSubnetId string = spokeVnet.properties.subnets[0].id
output privateEndpointsSubnetId string = spokeVnet.properties.subnets[1].id
output containerAppsLbIp string = '' // populated after Container Apps env deployment
