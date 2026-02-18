// ============================================================
// modules/fortigate.bicep
// FortiGate Active-Passive HA pair (VMSS-based)
// Marketplace image: Fortinet FortiGate Next-Generation Firewall
// ============================================================
param location string
param env string
param adminUsername string
@secure()
param adminPassword string
param vmSku string
param imageVersion string
param externalSubnetId string
param internalSubnetId string
param externalLbBackendPoolId string
param internalLbBackendPoolId string
param externalLbNatPoolId string

var fgName = 'vmss-fortigate-${env}'

// Storage account for FortiGate boot diagnostics
resource diagStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stfgdiag${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}

// FortiGate custom data (bootstrap config)
// This injects initial FortiOS config to set up interfaces,
// routing, health check probe response, and FGCP HA.
var fortiGateCustomData = base64('''
config system global
  set hostname fortigate-${env}
  set admintimeout 60
end
config system interface
  edit port1
    set mode dhcp
    set allowaccess ping https ssh fgfm
    set description "external"
  next
  edit port2
    set mode dhcp
    set allowaccess ping https
    set description "internal"
  next
end
config system probe-response
  set mode http-probe
  set http-probe-value OK
  set port 8008
end
config router static
  edit 1
    set gateway 10.0.1.1
    set device port1
  next
  edit 2
    set dst 10.1.0.0/16
    set gateway 10.0.2.1
    set device port2
  next
end
''')

// ── FortiGate VMSS ─────────────────────────────────────────
resource fortigateVmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: fgName
  location: location
  sku: {
    name: vmSku
    capacity: 2 // Active-Passive pair
  }
  plan: {
    name: 'fortinet_fg-vm_payg_2023'
    publisher: 'fortinet'
    product: 'fortinet_fortigate-vm_v5'
  }
  properties: {
    orchestrationMode: 'Uniform'
    upgradePolicy: { mode: 'Manual' }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'fgt-${env}'
        adminUsername: adminUsername
        adminPassword: adminPassword
        customData: fortiGateCustomData
      }
      storageProfile: {
        imageReference: {
          publisher: 'fortinet'
          offer: 'fortinet_fortigate-vm_v5'
          sku: 'fortinet_fg-vm_payg_2023'
          version: imageVersion
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: { storageAccountType: 'Premium_LRS' }
          diskSizeGB: 64
        }
        dataDisks: [
          {
            lun: 0
            createOption: 'Empty'
            diskSizeGB: 30
            managedDisk: { storageAccountType: 'Premium_LRS' }
          }
        ]
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          // Port1 — External NIC
          {
            name: 'nic-external'
            properties: {
              primary: true
              enableIPForwarding: true
              enableAcceleratedNetworking: true
              networkSecurityGroup: null // NSG applied at subnet level
              ipConfigurations: [
                {
                  name: 'ipconfig-external'
                  properties: {
                    subnet: { id: externalSubnetId }
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: [
                      { id: externalLbBackendPoolId }
                    ]
                    loadBalancerInboundNatPools: [
                      { id: externalLbNatPoolId }
                    ]
                  }
                }
              ]
            }
          }
          // Port2 — Internal NIC
          {
            name: 'nic-internal'
            properties: {
              primary: false
              enableIPForwarding: true
              enableAcceleratedNetworking: true
              ipConfigurations: [
                {
                  name: 'ipconfig-internal'
                  properties: {
                    subnet: { id: internalSubnetId }
                    privateIPAddressVersion: 'IPv4'
                    loadBalancerBackendAddressPools: [
                      { id: internalLbBackendPoolId }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
          storageUri: diagStorage.properties.primaryEndpoints.blob
        }
      }
    }
  }
}

output fortiGateVmssName string = fortigateVmss.name
