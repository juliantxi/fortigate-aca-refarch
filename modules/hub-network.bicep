// ============================================================
// modules/hub-network.bicep
// Hub VNet, subnets, NSGs, Load Balancers, Public IP
// ============================================================
param location string
param env string

// ── VNet & Subnets ─────────────────────────────────────────
var hubVnetName = 'vnet-hub-${env}'
var hubVnetPrefix = '10.0.0.0/16'

var externalSubnetName = 'snet-external'
var externalSubnetPrefix = '10.0.1.0/24'

var internalSubnetName = 'snet-internal'
var internalSubnetPrefix = '10.0.2.0/24'

var dnsResolverInboundSubnetName = 'snet-dns-inbound'
var dnsResolverInboundSubnetPrefix = '10.0.3.0/28' // min /28 for DNS resolver

// ── NSGs ───────────────────────────────────────────────────
resource nsgExternal 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-external-${env}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-https-inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['443', '80']
        }
      }
      {
        name: 'allow-fortigate-mgmt'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet' // Restrict to your admin IP in production!
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['8443', '8444'] // FortiGate HTTPS mgmt ports
        }
      }
      {
        name: 'allow-ha-heartbeat'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Udp'
          sourceAddressPrefix: externalSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '703'
        }
      }
    ]
  }
}

resource nsgInternal 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-internal-${env}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-from-external-subnet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: externalSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'allow-from-spoke'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '10.1.0.0/16' // spoke VNet CIDR
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ── Hub VNet ───────────────────────────────────────────────
resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: hubVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [hubVnetPrefix]
    }
    subnets: [
      {
        name: externalSubnetName
        properties: {
          addressPrefix: externalSubnetPrefix
          networkSecurityGroup: { id: nsgExternal.id }
        }
      }
      {
        name: internalSubnetName
        properties: {
          addressPrefix: internalSubnetPrefix
          networkSecurityGroup: { id: nsgInternal.id }
        }
      }
      {
        name: dnsResolverInboundSubnetName
        properties: {
          addressPrefix: dnsResolverInboundSubnetPrefix
          delegations: [
            {
              name: 'dns-resolver-delegation'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
    ]
  }
}

// ── Public IP (FortiGate external) ─────────────────────────
resource fortiGatePip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-fortigate-${env}'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'fortigate-${env}-${uniqueString(resourceGroup().id)}'
    }
  }
}

// ── External Load Balancer (in front of FortiGate) ─────────
resource externalLb 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: 'lb-external-${env}'
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-external'
        properties: {
          publicIPAddress: { id: fortiGatePip.id }
        }
      }
    ]
    backendAddressPools: [
      { name: 'be-fortigate' }
    ]
    probes: [
      {
        name: 'probe-https'
        properties: {
          protocol: 'Https'
          port: 8443
          requestPath: '/'
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-https'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-external-${env}', 'fe-external')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-external-${env}', 'be-fortigate')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-external-${env}', 'probe-https')
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
          enableFloatingIP: true // Required for FortiGate HA
          idleTimeoutInMinutes: 4
        }
      }
      {
        name: 'rule-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-external-${env}', 'fe-external')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-external-${env}', 'be-fortigate')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-external-${env}', 'probe-https')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: true
          idleTimeoutInMinutes: 4
        }
      }
    ]
    // NAT rules for per-instance mgmt access
    inboundNatPools: [
      {
        name: 'natpool-fortigate-mgmt'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-external-${env}', 'fe-external')
          }
          protocol: 'Tcp'
          frontendPortRangeStart: 50443
          frontendPortRangeEnd: 50444
          backendPort: 8443
          enableFloatingIP: false
        }
      }
    ]
  }
}

// ── Internal Load Balancer (FortiGate → Spoke) ─────────────
resource internalLb 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: 'lb-internal-${env}'
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-internal'
        properties: {
          subnet: {
            id: hubVnet.properties.subnets[1].id // internal subnet
          }
          privateIPAddress: '10.0.2.4'
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
    backendAddressPools: [
      { name: 'be-fortigate-internal' }
    ]
    probes: [
      {
        name: 'probe-internal'
        properties: {
          protocol: 'Tcp'
          port: 8008 // FortiGate internal probe port
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-haports'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-internal-${env}', 'fe-internal')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-internal-${env}', 'be-fortigate-internal')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-internal-${env}', 'probe-internal')
          }
          protocol: 'All' // HA ports — routes all traffic
          frontendPort: 0
          backendPort: 0
          enableFloatingIP: true
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// ── Outputs ────────────────────────────────────────────────
output hubVnetName string = hubVnet.name
output hubVnetId string = hubVnet.id
output externalSubnetId string = hubVnet.properties.subnets[0].id
output internalSubnetId string = hubVnet.properties.subnets[1].id
output dnsResolverInboundSubnetId string = hubVnet.properties.subnets[2].id
output fortiGatePublicIp string = fortiGatePip.properties.ipAddress
output fortiGateInternalLbIp string = '10.0.2.4'
output externalLbBackendPoolId string = externalLb.properties.backendAddressPools[0].id
output internalLbBackendPoolId string = internalLb.properties.backendAddressPools[0].id
output externalLbNatPoolId string = externalLb.properties.inboundNatPools[0].id
