import HiveCore
import ColonyCore

public struct ColonyRuntime: Sendable {
    public let runControl: ColonyRunControl

    public init(
        threadID: HiveThreadID,
        runtime: HiveRuntime<ColonySchema>,
        options: HiveRunOptions
    ) {
        self.runControl = ColonyRunControl(
            threadID: threadID,
            runtime: runtime,
            options: options
        )
    }

    public init(runControl: ColonyRunControl) {
        self.runControl = runControl
    }
}
