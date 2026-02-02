// ========================================
// NSP Resource Association Module
// ========================================
// Associates a PaaS resource with a Network Security Perimeter
// This enables network isolation for the target resource
// ========================================

@description('Network Security Perimeter name')
param nspName string

@description('NSP Profile resource ID')
param profileId string

@description('Target resource ID to associate with NSP')
param targetResourceId string

@description('Association name (must be unique within NSP)')
param associationName string

@description('Location for the association resource')
param location string = resourceGroup().location

@description('Access mode for the association')
@allowed([
  'Learning'    // Monitor mode - logs violations but doesn't block
  'Enforced'    // Strict mode - blocks non-compliant traffic
])
param accessMode string = 'Learning'

// ========================================
// Reference to existing NSP
// ========================================

resource networkSecurityPerimeter 'Microsoft.Network/networkSecurityPerimeters@2023-07-01-preview' existing = {
  name: nspName
}

// ========================================
// Resource Association
// ========================================

resource nspAssociation 'Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2023-07-01-preview' = {
  parent: networkSecurityPerimeter
  name: associationName
  location: location
  properties: {
    privateLinkResource: {
      id: targetResourceId
    }
    profile: {
      id: profileId
    }
    accessMode: accessMode
  }
}

// ========================================
// Outputs
// ========================================

@description('Resource association ID')
output associationId string = nspAssociation.id

@description('Resource association name')
output associationNameOut string = nspAssociation.name
