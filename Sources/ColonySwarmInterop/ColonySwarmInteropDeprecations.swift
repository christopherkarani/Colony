// ColonySwarmInteropDeprecations.swift
// Consolidated deprecated typealiases for the ColonySwarmInterop module.
// These exist solely for backward compatibility — prefer the canonical names.

import Foundation
import ColonyCore

// MARK: - From SwarmToolBridge.swift

@available(*, deprecated, renamed: "ColonySwarmToolRegistration")
public typealias SwarmToolRegistration = ColonySwarmToolRegistration

@available(*, deprecated, renamed: "ColonySwarmToolBridge")
public typealias SwarmToolBridge = ColonySwarmToolBridge

// MARK: - From SwarmMemoryAdapter.swift

@available(*, deprecated, renamed: "ColonySwarmMemoryAdapter")
public typealias SwarmMemoryAdapter = ColonySwarmMemoryAdapter

// MARK: - From SwarmSubagentAdapter.swift

@available(*, deprecated, renamed: "ColonySwarmSubagentAdapter")
public typealias SwarmSubagentAdapter = ColonySwarmSubagentAdapter
