// ============================================================
// modules/container-apps.bicep
// Log Analytics, Container Apps Environment (internal), sample app
// ============================================================
param location string
param env string
param containerAppsSubnetId string

// ── Log Analytics Workspace ────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-container-apps-${env}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Container Apps Environment (internal/private) ──────────
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: 'cae-${env}'
  location: location
  properties: {
    // 'internal' means no public endpoint — only private IP
    vnetConfiguration: {
      internal: true
      infrastructureSubnetId: containerAppsSubnetId
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        // Consumption profile (serverless, lowest cost)
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false // Set true for production in regions that support it
  }
}

// ── Sample Container App ───────────────────────────────────
resource sampleApp 'Microsoft.App/containerApps@2023-11-02-preview' = {
  name: 'app-sample-${env}'
  location: location
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: {
        external: false        // Internal ingress only — exposed via FortiGate
        targetPort: 80
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'sample'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'PORT'
              value: '80'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// ── Outputs ────────────────────────────────────────────────
output containerAppsEnvId string = containerAppsEnv.id
output staticIp string = containerAppsEnv.properties.staticIp
output defaultDomain string = containerAppsEnv.properties.defaultDomain
output sampleAppFqdn string = sampleApp.properties.configuration.ingress.fqdn
