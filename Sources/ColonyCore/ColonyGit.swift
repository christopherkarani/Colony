public struct ColonyGitStatusRequest: Sendable, Equatable, Codable {
    public var repositoryPath: ColonyVirtualPath?
    public var includeUntracked: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        includeUntracked: Bool = true
    ) {
        self.repositoryPath = repositoryPath
        self.includeUntracked = includeUntracked
    }
}

public struct ColonyGitStatusEntry: Sendable, Equatable, Codable {
    public enum State: String, Sendable, Codable, CaseIterable {
        case added
        case modified
        case deleted
        case renamed
        case copied
        case conflicted
        case untracked
    }

    public var path: String
    public var state: State

    public init(path: String, state: State) {
        self.path = path
        self.state = state
    }
}

public struct ColonyGitDiffRequest: Sendable, Equatable, Codable {
    public var repositoryPath: ColonyVirtualPath?
    public var baseRef: String?
    public var headRef: String?
    public var pathspec: String?
    public var staged: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        baseRef: String? = nil,
        headRef: String? = nil,
        pathspec: String? = nil,
        staged: Bool = false
    ) {
        self.repositoryPath = repositoryPath
        self.baseRef = baseRef
        self.headRef = headRef
        self.pathspec = pathspec
        self.staged = staged
    }
}

public struct ColonyGitCommitRequest: Sendable, Equatable, Codable {
    public var repositoryPath: ColonyVirtualPath?
    public var message: String
    public var includeAll: Bool
    public var amend: Bool
    public var signoff: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        message: String,
        includeAll: Bool = true,
        amend: Bool = false,
        signoff: Bool = false
    ) {
        self.repositoryPath = repositoryPath
        self.message = message
        self.includeAll = includeAll
        self.amend = amend
        self.signoff = signoff
    }
}

public struct ColonyGitBranchRequest: Sendable, Equatable, Codable {
    public enum Operation: String, Sendable, Codable, CaseIterable {
        case create
        case checkout
        case delete
        case list
    }

    public var repositoryPath: ColonyVirtualPath?
    public var operation: Operation
    public var name: String?
    public var startPoint: String?
    public var force: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        operation: Operation = .list,
        name: String? = nil,
        startPoint: String? = nil,
        force: Bool = false
    ) {
        self.repositoryPath = repositoryPath
        self.operation = operation
        self.name = name
        self.startPoint = startPoint
        self.force = force
    }
}

public struct ColonyGitPushRequest: Sendable, Equatable, Codable {
    public var repositoryPath: ColonyVirtualPath?
    public var remote: String?
    public var branch: String?
    public var force: Bool
    public var forceWithLease: Bool
    public var setUpstream: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        remote: String? = nil,
        branch: String? = nil,
        force: Bool = false,
        forceWithLease: Bool = false,
        setUpstream: Bool = false
    ) {
        self.repositoryPath = repositoryPath
        self.remote = remote
        self.branch = branch
        self.force = force
        self.forceWithLease = forceWithLease
        self.setUpstream = setUpstream
    }
}

public struct ColonyGitPreparePullRequestRequest: Sendable, Equatable, Codable {
    public var repositoryPath: ColonyVirtualPath?
    public var baseBranch: String
    public var headBranch: String
    public var title: String
    public var body: String
    public var draft: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        baseBranch: String,
        headBranch: String,
        title: String,
        body: String,
        draft: Bool = false
    ) {
        self.repositoryPath = repositoryPath
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.title = title
        self.body = body
        self.draft = draft
    }
}

// MARK: - Response Types (New Naming)

public struct ColonyGitStatusResponse: Sendable, Equatable, Codable {
    public var currentBranch: String?
    public var upstreamBranch: String?
    public var aheadBy: Int
    public var behindBy: Int
    public var entries: [ColonyGitStatusEntry]

    public init(
        currentBranch: String? = nil,
        upstreamBranch: String? = nil,
        aheadBy: Int = 0,
        behindBy: Int = 0,
        entries: [ColonyGitStatusEntry] = []
    ) {
        self.currentBranch = currentBranch
        self.upstreamBranch = upstreamBranch
        self.aheadBy = aheadBy
        self.behindBy = behindBy
        self.entries = entries
    }
}

public struct ColonyGitDiffResponse: Sendable, Equatable, Codable {
    public var patch: String

    public init(patch: String) {
        self.patch = patch
    }
}

public struct ColonyGitCommitResponse: Sendable, Equatable, Codable {
    public var commitHash: String
    public var summary: String

    public init(commitHash: String, summary: String) {
        self.commitHash = commitHash
        self.summary = summary
    }
}

public struct ColonyGitBranchResponse: Sendable, Equatable, Codable {
    public var currentBranch: String?
    public var branches: [String]
    public var detail: String?

    public init(
        currentBranch: String? = nil,
        branches: [String] = [],
        detail: String? = nil
    ) {
        self.currentBranch = currentBranch
        self.branches = branches
        self.detail = detail
    }
}

public struct ColonyGitPushResponse: Sendable, Equatable, Codable {
    public var remote: String
    public var branch: String
    public var summary: String

    public init(remote: String, branch: String, summary: String) {
        self.remote = remote
        self.branch = branch
        self.summary = summary
    }
}

public struct ColonyGitPreparePullRequestResponse: Sendable, Equatable, Codable {
    public var baseBranch: String
    public var headBranch: String
    public var title: String
    public var body: String
    public var draft: Bool
    public var summary: String?

    public init(
        baseBranch: String,
        headBranch: String,
        title: String,
        body: String,
        draft: Bool = false,
        summary: String? = nil
    ) {
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.title = title
        self.body = body
        self.draft = draft
        self.summary = summary
    }
}

public protocol ColonyGitService: Sendable {
    func getStatus(_ request: ColonyGitStatusRequest) async throws -> ColonyGitStatusResponse
    func getDiff(_ request: ColonyGitDiffRequest) async throws -> ColonyGitDiffResponse
    func createCommit(_ request: ColonyGitCommitRequest) async throws -> ColonyGitCommitResponse
    func manageBranch(_ request: ColonyGitBranchRequest) async throws -> ColonyGitBranchResponse
    func pushChanges(_ request: ColonyGitPushRequest) async throws -> ColonyGitPushResponse
    func preparePullRequest(_ request: ColonyGitPreparePullRequestRequest) async throws -> ColonyGitPreparePullRequestResponse
}

// MARK: - Deprecated Type Aliases and Shims

@available(*, deprecated, renamed: "ColonyGitService")
public typealias ColonyGitBackend = ColonyGitService

@available(*, deprecated, renamed: "ColonyGitStatusResponse")
public typealias ColonyGitStatusResult = ColonyGitStatusResponse

@available(*, deprecated, renamed: "ColonyGitDiffResponse")
public typealias ColonyGitDiffResult = ColonyGitDiffResponse

@available(*, deprecated, renamed: "ColonyGitCommitResponse")
public typealias ColonyGitCommitResult = ColonyGitCommitResponse

@available(*, deprecated, renamed: "ColonyGitBranchResponse")
public typealias ColonyGitBranchResult = ColonyGitBranchResponse

@available(*, deprecated, renamed: "ColonyGitPushResponse")
public typealias ColonyGitPushResult = ColonyGitPushResponse

@available(*, deprecated, renamed: "ColonyGitPreparePullRequestResponse")
public typealias ColonyGitPreparePullRequestResult = ColonyGitPreparePullRequestResponse

public extension ColonyGitService {
    @available(*, deprecated, renamed: "getStatus")
    func status(_ request: ColonyGitStatusRequest) async throws -> ColonyGitStatusResponse {
        try await getStatus(request)
    }

    @available(*, deprecated, renamed: "getDiff")
    func diff(_ request: ColonyGitDiffRequest) async throws -> ColonyGitDiffResponse {
        try await getDiff(request)
    }

    @available(*, deprecated, renamed: "createCommit")
    func commit(_ request: ColonyGitCommitRequest) async throws -> ColonyGitCommitResponse {
        try await createCommit(request)
    }

    @available(*, deprecated, renamed: "manageBranch")
    func branch(_ request: ColonyGitBranchRequest) async throws -> ColonyGitBranchResponse {
        try await manageBranch(request)
    }

    @available(*, deprecated, renamed: "pushChanges")
    func push(_ request: ColonyGitPushRequest) async throws -> ColonyGitPushResponse {
        try await pushChanges(request)
    }
}
