// ============================================================
// main.bicepparam — Parameter file for prod deployment
// ============================================================
using 'main.bicep'

param location = 'australiaeast'
param env = 'prod'
param fortiGateAdminUsername = 'fgtadmin'
param fortiGateAdminPassword = '' // Set via --parameters or Key Vault reference
param fortiGateVmSku = 'Standard_F4s_v2'
param fortiGateImageVersion = 'latest'


// ============================================================
// DEPLOYMENT GUIDE
// ============================================================
//
// Prerequisites:
//   az extension add --name containerapp
//   az provider register --namespace Microsoft.App
//   az provider register --namespace Microsoft.OperationalInsights
//   az provider register --namespace Microsoft.Network
//
// ── Step 1: Accept FortiGate Marketplace terms ─────────────
//
//   az vm image terms accept \
//     --publisher fortinet \
//     --offer fortinet_fortigate-vm_v5 \
//     --plan fortinet_fg-vm_payg_2023
//
// ── Step 2: First deployment pass ─────────────────────────
//   Deploys networking, FortiGate, DNS resolver, and Container Apps env.
//   The private DNS wildcard A record is skipped (no IP yet).
//
//   az deployment sub create \
//     --name deploy-hub-spoke \
//     --location australiaeast \
//     --template-file main.bicep \
//     --parameters main.bicepparam \
//     --parameters fortiGateAdminPassword='<your-secure-password>'
//
// ── Step 3: Get Container Apps static IP ──────────────────
//
//   STATIC_IP=$(az containerapp env show \
//     --name cae-prod \
//     --resource-group rg-spoke-prod \
//     --query properties.staticIp -o tsv)
//
//   echo "Container Apps static IP: $STATIC_IP"
//
// ── Step 4: Second deployment pass (DNS record) ────────────
//   Pass the static IP to wire up the private DNS A record.
//
//   az deployment sub create \
//     --name deploy-hub-spoke-dns \
//     --location australiaeast \
//     --template-file main.bicep \
//     --parameters main.bicepparam \
//     --parameters fortiGateAdminPassword='<your-secure-password>' \
//     --parameters containerAppsLbIp=$STATIC_IP
//
//   NOTE: Add containerAppsLbIp as a param to main.bicep and pass it
//         down to the privateDns module for the second pass.
//
// ── Step 5: Configure FortiGate VIP & Policy ──────────────
//   After deployment, SSH to the FortiGate (or use the web console via
//   the NAT rule on port 50443 of the public IP) and configure:
//
//   a) Virtual IP (DNAT — public IP → Container Apps internal LB IP):
//
//      config firewall vip
//        edit "vip-container-apps-https"
//          set extintf "port1"
//          set mappedip "$STATIC_IP"
//          set extport 443
//          set mappedport 443
//          set portforward enable
//        next
//      end
//
//   b) Firewall Policy (allow inbound HTTPS to VIP):
//
//      config firewall policy
//        edit 1
//          set name "allow-inbound-https-to-aca"
//          set srcintf "port1"
//          set dstintf "port2"
//          set action accept
//          set srcaddr "all"
//          set dstaddr "vip-container-apps-https"
//          set schedule "always"
//          set service "HTTPS"
//          set utm-status enable
//          set ssl-ssh-profile "certificate-inspection"
//          set av-profile "default"
//          set webfilter-profile "default"
//          set logtraffic all
//        next
//      end
//
//   c) Outbound policy (Container Apps → Internet via FortiGate):
//
//      config firewall policy
//        edit 2
//          set name "allow-outbound-from-aca"
//          set srcintf "port2"
//          set dstintf "port1"
//          set action accept
//          set srcaddr "10.1.0.0/23"
//          set dstaddr "all"
//          set schedule "always"
//          set service "ALL"
//          set nat enable
//          set logtraffic all
//        next
//      end
//
// ── Step 6: DNS validation ─────────────────────────────────
//
//   From a VM in the hub or spoke VNet:
//   nslookup app-sample-prod.<unique>.<region>.azurecontainerapps.io
//   # Should resolve to $STATIC_IP
//
// ── Step 7: Test end-to-end ────────────────────────────────
//   curl -v https://<fortigate-public-ip>/
//   # Should return the Container Apps hello world page
//
// ── Useful resource IDs after deployment ──────────────────
//
//   FortiGate Public IP:
//     az deployment sub show --name deploy-hub-spoke \
//       --query properties.outputs.fortiGatePublicIp.value -o tsv
//
//   Container Apps default domain:
//     az deployment sub show --name deploy-hub-spoke \
//       --query properties.outputs.containerAppsDefaultDomain.value -o tsv
