// ============================================================
// modules/private-dns.bicep
// Private DNS Zone for Container Apps internal domain
// ============================================================
param env string
param hubVnetId string
param spokeVnetId string
param containerAppsLbIp string // Pass staticIp from container-apps module output

// The domain is dynamic per environment; the actual value comes from
// containerAppsEnv.properties.defaultDomain after deployment.
// Pattern: <unique>.<region>.azurecontainerapps.io
// We create a wildcard A record pointing to the static IP.

var privateDnsZoneName = 'privatelink.azurecontainerapps.io'

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

// Link to Hub VNet
resource dnsLinkHub 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'link-hub'
  parent: privateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: { id: hubVnetId }
    registrationEnabled: false
  }
}

// Link to Spoke VNet
resource dnsLinkSpoke 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'link-spoke'
  parent: privateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: { id: spokeVnetId }
    registrationEnabled: false
  }
}

// Wildcard A record — points all *.azurecontainerapps.io queries to the
// Container Apps Environment internal load balancer IP.
// NOTE: containerAppsLbIp will be empty on first deployment; run a second
// deployment pass after the Container Apps env is created to set this.
resource wildcardARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = if (!empty(containerAppsLbIp)) {
  name: '*'
  parent: privateDnsZone
  properties: {
    ttl: 300
    aRecords: [
      { ipv4Address: containerAppsLbIp }
    ]
  }
}


// ============================================================
// modules/dns-resolver.bicep
// Azure DNS Private Resolver — allows FortiGate and on-prem
// to resolve private DNS zones without custom DNS servers.
// ============================================================
// (Paste into separate file: modules/dns-resolver.bicep)

/*
param location string
param env string
param hubVnetId string
param resolverInboundSubnetId string

resource dnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: 'dnsresolver-${env}'
  location: location
  properties: {
    virtualNetwork: { id: hubVnetId }
  }
}

resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  name: 'inbound-endpoint'
  parent: dnsResolver
  location: location
  properties: {
    ipConfigurations: [
      {
        subnet: { id: resolverInboundSubnetId }
        privateIpAllocationMethod: 'Dynamic'
      }
    ]
  }
}

output inboundEndpointIp string = inboundEndpoint.properties.ipConfigurations[0].privateIpAddress
*/


// ============================================================
// modules/vnet-peering.bicep
// Generic reusable VNet peering module
// ============================================================
// (Paste into separate file: modules/vnet-peering.bicep)

/*
param localVnetName string
param remoteVnetId string
param peeringName string

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: '${localVnetName}/${peeringName}'
  properties: {
    remoteVirtualNetwork: { id: remoteVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
*/
