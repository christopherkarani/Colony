// ColonyDeprecations.swift
// Consolidated deprecated typealiases for the Colony module.
// These exist solely for backward compatibility — prefer the canonical names.

import Foundation
import ColonyCore

// MARK: - From ColonyPublicAPI.swift

@available(*, deprecated, renamed: "ColonyModel.FoundationModelConfiguration")
public typealias ColonyFoundationModelConfiguration = ColonyModel.FoundationModelConfiguration
@available(*, deprecated, renamed: "ColonyModel.OnDevicePolicy")
public typealias ColonyOnDeviceModelPolicy = ColonyModel.OnDevicePolicy
@available(*, deprecated, renamed: "ColonyModel.ProviderID")
public typealias ColonyProviderID = ColonyModel.ProviderID
@available(*, deprecated, renamed: "ColonyModel.Provider")
public typealias ColonyProvider = ColonyModel.Provider
@available(*, deprecated, renamed: "ColonyModel.RoutingPolicy")
public typealias ColonyProviderRoutingPolicy = ColonyModel.RoutingPolicy
