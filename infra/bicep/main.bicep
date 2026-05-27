// ============================================================================
// Main Bicep Template - Enterprise Template
// ============================================================================
// Deploy with:
//   az deployment group create -g <rg> -f main.bicep -p environment=dev
// ============================================================================

@description('Environment name')
@allowed(['dev', 'staging', 'production'])
param environment string

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Project name for resource naming')
param projectName string

@description('Common tags for all resources')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

#disable-next-line no-unused-vars
var commonTags = union(tags, {
  environment: environment
  managedBy: 'bicep'
  project: projectName
})

var namePrefix = '${projectName}-${environment}'

// ============================================================================
// Modules
// ============================================================================

// Example module reference:
// module networking 'modules/networking.bicep' = {
//   name: 'networking-deployment'
//   params: {
//     location: location
//     namePrefix: namePrefix
//     tags: commonTags
//   }
// }

// ============================================================================
// Outputs
// ============================================================================

output namePrefix string = namePrefix
output location string = location
