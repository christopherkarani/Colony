import HiveCore
import ColonyCore

public protocol ColonyCapabilityReportingModelClient: HiveModelClient {
    var colonyModelCapabilities: ColonyModelCapabilities { get }
}

public protocol ColonyCapabilityReportingModelRouter: HiveModelRouter {
    func colonyModelCapabilities(hints: HiveInferenceHints?) -> ColonyModelCapabilities
}
