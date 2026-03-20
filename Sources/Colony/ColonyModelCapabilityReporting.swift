import HiveCore
import ColonyCore

public protocol ColonyCapabilityReportingModelClient: ColonyModelClient {
    var colonyModelCapabilities: ColonyModelCapabilities { get }
}

package protocol ColonyCapabilityReportingHiveModelClient: HiveModelClient {
    var colonyModelCapabilities: ColonyModelCapabilities { get }
}

package protocol ColonyCapabilityReportingHiveModelRouter: HiveModelRouter {
    func colonyModelCapabilities(hints: HiveInferenceHints?) -> ColonyModelCapabilities
}

public protocol ColonyCapabilityReportingModelRouter: ColonyModelRouter {
    func colonyModelCapabilities(hints: ColonyInferenceHints?) -> ColonyModelCapabilities
}
