// ============================================================
// main.bicep — Entry point
// ============================================================
targetScope = 'subscription'

@description('Primary Azure region for all resources')
param location string = 'australiaeast'

@description('Environment tag (e.g. prod, staging)')
param env string = 'prod'

@description('FortiGate admin username')
param fortiGateAdminUsername string

@secure()
@description('FortiGate admin password')
param fortiGateAdminPassword string

@description('FortiGate VM SKU')
param fortiGateVmSku string = 'Standard_F4s_v2'

@description('Fortinet image version')
param fortiGateImageVersion string = 'latest'

// ── Resource Groups ────────────────────────────────────────
resource rgHub 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-hub-${env}'
  location: location
}

resource rgSpoke 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-spoke-${env}'
  location: location
}

// ── Hub Networking ─────────────────────────────────────────
module hubNetwork 'modules/hub-network.bicep' = {
  name: 'hubNetwork'
  scope: rgHub
  params: {
    location: location
    env: env
  }
}

// ── Spoke Networking ───────────────────────────────────────
module spokeNetwork 'modules/spoke-network.bicep' = {
  name: 'spokeNetwork'
  scope: rgSpoke
  params: {
    location: location
    env: env
    fortiGateInternalLbIp: hubNetwork.outputs.fortiGateInternalLbIp
  }
}

// ── VNet Peering ───────────────────────────────────────────
module peeringHubToSpoke 'modules/vnet-peering.bicep' = {
  name: 'peeringHubToSpoke'
  scope: rgHub
  params: {
    localVnetName: hubNetwork.outputs.hubVnetName
    remoteVnetId: spokeNetwork.outputs.spokeVnetId
    peeringName: 'hub-to-spoke'
  }
}

module peeringSpokeToHub 'modules/vnet-peering.bicep' = {
  name: 'peeringSpokeToHub'
  scope: rgSpoke
  params: {
    localVnetName: spokeNetwork.outputs.spokeVnetName
    remoteVnetId: hubNetwork.outputs.hubVnetId
    peeringName: 'spoke-to-hub'
  }
}

// ── FortiGate NVA ──────────────────────────────────────────
module fortigate 'modules/fortigate.bicep' = {
  name: 'fortigate'
  scope: rgHub
  params: {
    location: location
    env: env
    adminUsername: fortiGateAdminUsername
    adminPassword: fortiGateAdminPassword
    vmSku: fortiGateVmSku
    imageVersion: fortiGateImageVersion
    externalSubnetId: hubNetwork.outputs.externalSubnetId
    internalSubnetId: hubNetwork.outputs.internalSubnetId
    externalLbBackendPoolId: hubNetwork.outputs.externalLbBackendPoolId
    internalLbBackendPoolId: hubNetwork.outputs.internalLbBackendPoolId
    externalLbNatPoolId: hubNetwork.outputs.externalLbNatPoolId
  }
}

// ── DNS Private Resolver ───────────────────────────────────
module dnsResolver 'modules/dns-resolver.bicep' = {
  name: 'dnsResolver'
  scope: rgHub
  params: {
    location: location
    env: env
    hubVnetId: hubNetwork.outputs.hubVnetId
    resolverInboundSubnetId: hubNetwork.outputs.dnsResolverInboundSubnetId
  }
}

// ── Private DNS Zone ───────────────────────────────────────
module privateDns 'modules/private-dns.bicep' = {
  name: 'privateDns'
  scope: rgHub
  params: {
    env: env
    hubVnetId: hubNetwork.outputs.hubVnetId
    spokeVnetId: spokeNetwork.outputs.spokeVnetId
    containerAppsLbIp: spokeNetwork.outputs.containerAppsLbIp
  }
  dependsOn: [spokeNetwork]
}

// ── Container Apps Environment ─────────────────────────────
module containerApps 'modules/container-apps.bicep' = {
  name: 'containerApps'
  scope: rgSpoke
  params: {
    location: location
    env: env
    containerAppsSubnetId: spokeNetwork.outputs.containerAppsSubnetId
  }
}

// ── Outputs ────────────────────────────────────────────────
output fortiGatePublicIp string = hubNetwork.outputs.fortiGatePublicIp
output containerAppsDefaultDomain string = containerApps.outputs.defaultDomain
