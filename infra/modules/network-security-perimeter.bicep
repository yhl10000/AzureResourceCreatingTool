// ========================================
// Network Security Perimeter Module
// ========================================
// Creates a Network Security Perimeter (NSP) with profile and access rules
// Resources can be associated to this NSP for network isolation
// ========================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Project name for resource naming')
param projectName string

@description('Environment (dev, staging, prod)')
param environment string = 'dev'

@description('Allowed inbound IP address prefixes (CIDR notation)')
param allowedInboundAddressPrefixes array = []

@description('Allowed outbound FQDNs')
param allowedOutboundFqdns array = []

@description('Tags for all resources')
param tags object = {}

// ========================================
// Variables
// ========================================

var nspName = 'nsp-${projectName}-${environment}'
var profileName = 'profile-${projectName}-${environment}'

// ========================================
// Network Security Perimeter
// ========================================

resource networkSecurityPerimeter 'Microsoft.Network/networkSecurityPerimeters@2023-07-01-preview' = {
  name: nspName
  location: location
  tags: tags
  properties: {}
}

// ========================================
// NSP Profile
// ========================================

resource nspProfile 'Microsoft.Network/networkSecurityPerimeters/profiles@2023-07-01-preview' = {
  parent: networkSecurityPerimeter
  name: profileName
  location: location
  properties: {}
}

// ========================================
// Inbound Access Rule (if IP prefixes provided)
// ========================================

resource inboundAccessRule 'Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2023-07-01-preview' = if (length(allowedInboundAddressPrefixes) > 0) {
  parent: nspProfile
  name: 'inbound-allowed-ips'
  location: location
  properties: {
    direction: 'Inbound'
    addressPrefixes: allowedInboundAddressPrefixes
    fullyQualifiedDomainNames: []
    subscriptions: []
    emailAddresses: []
    phoneNumbers: []
  }
}

// ========================================
// Outbound Access Rule (if FQDNs provided)
// ========================================

resource outboundAccessRule 'Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2023-07-01-preview' = if (length(allowedOutboundFqdns) > 0) {
  parent: nspProfile
  name: 'outbound-allowed-fqdns'
  location: location
  properties: {
    direction: 'Outbound'
    addressPrefixes: []
    fullyQualifiedDomainNames: allowedOutboundFqdns
    subscriptions: []
    emailAddresses: []
    phoneNumbers: []
  }
}

// ========================================
// Outputs
// ========================================

@description('Network Security Perimeter resource ID')
output nspId string = networkSecurityPerimeter.id

@description('Network Security Perimeter name')
output nspName string = networkSecurityPerimeter.name

@description('NSP Profile resource ID')
output profileId string = nspProfile.id

@description('NSP Profile name')
output profileName string = nspProfile.name
