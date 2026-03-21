// ColonyControlPlaneDeprecations.swift
// Consolidated deprecated typealiases for the ColonyControlPlane module.
// These exist solely for backward compatibility — prefer the canonical names.

import Foundation
import ColonyCore

// MARK: - From ColonyControlPlaneTransport.swift

@available(*, deprecated, renamed: "ControlPlane.TransportKind")
public typealias ColonyControlPlaneTransportKind = ControlPlane.TransportKind

@available(*, deprecated, renamed: "ControlPlane.HTTPMethod")
public typealias ColonyControlPlaneHTTPMethod = ControlPlane.HTTPMethod

@available(*, deprecated, renamed: "ControlPlane.Operation")
public typealias ColonyControlPlaneOperation = ControlPlane.Operation

@available(*, deprecated, renamed: "ControlPlane.RouteDescriptor")
public typealias ColonyControlPlaneRouteDescriptor = ControlPlane.RouteDescriptor

@available(*, deprecated, renamed: "ControlPlaneTransport")
public typealias ColonyControlPlaneTransport = ControlPlaneTransport

@available(*, deprecated, renamed: "ControlPlaneTransport")
public typealias ColonyControlPlaneRESTTransport = ControlPlaneTransport

@available(*, deprecated, renamed: "ControlPlaneTransport")
public typealias ColonyControlPlaneSSETransport = ControlPlaneTransport

@available(*, deprecated, renamed: "ControlPlaneTransport")
public typealias ColonyControlPlaneWebSocketTransport = ControlPlaneTransport

// MARK: - From ColonyControlPlaneDomain.swift

@available(*, deprecated, renamed: "ControlPlane.RecordMetadata")
public typealias ColonyRecordMetadata = ControlPlane.RecordMetadata

@available(*, deprecated, renamed: "ControlPlane.ProjectRecord")
public typealias ColonyProjectRecord = ControlPlane.ProjectRecord

@available(*, deprecated, renamed: "ControlPlane.SessionVersionRecord")
public typealias ColonyProductSessionVersionRecord = ControlPlane.SessionVersionRecord

@available(*, deprecated, renamed: "ControlPlane.SessionShareRecord")
public typealias ColonyProductSessionShareRecord = ControlPlane.SessionShareRecord

@available(*, deprecated, renamed: "ControlPlane.SessionRecord")
public typealias ColonyProductSessionRecord = ControlPlane.SessionRecord

@available(*, deprecated, renamed: "ControlPlane.ProjectCreateInput")
public typealias ColonyProjectCreateInput = ControlPlane.ProjectCreateInput

@available(*, deprecated, renamed: "ControlPlane.SessionCreateInput")
public typealias ColonySessionCreateInput = ControlPlane.SessionCreateInput

@available(*, deprecated, renamed: "ControlPlane.SessionForkInput")
public typealias ColonySessionForkInput = ControlPlane.SessionForkInput

@available(*, deprecated, renamed: "ControlPlane.SessionShareInput")
public typealias ColonySessionShareInput = ControlPlane.SessionShareInput

@available(*, deprecated, renamed: "ControlPlane.ProjectStoreError")
public typealias ColonyProjectStoreError = ControlPlane.ProjectStoreError

@available(*, deprecated, renamed: "ControlPlane.SessionStoreError")
public typealias ColonySessionStoreError = ControlPlane.SessionStoreError

// MARK: - From ColonyProjectStore.swift

@available(*, deprecated, renamed: "ControlPlaneProjectStore")
public typealias ColonyProjectStore = ControlPlaneProjectStore

@available(*, deprecated, renamed: "InMemoryControlPlaneProjectStore")
package typealias InMemoryColonyProjectStore = InMemoryControlPlaneProjectStore

// MARK: - From ColonySessionStore.swift

@available(*, deprecated, renamed: "ControlPlane.SessionStore")
package typealias ColonySessionStore = ControlPlane.SessionStore

// MARK: - From ColonyControlPlaneService.swift

@available(*, deprecated, renamed: "ControlPlane.Service")
public typealias ColonyControlPlaneService = ControlPlane.Service
