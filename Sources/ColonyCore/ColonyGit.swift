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

public struct ColonyGitStatusResult: Sendable, Equatable, Codable {
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

public struct ColonyGitDiffResult: Sendable, Equatable, Codable {
    public var patch: String

    public init(patch: String) {
        self.patch = patch
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

public struct ColonyGitCommitResult: Sendable, Equatable, Codable {
    public var commitHash: String
    public var summary: String

    public init(commitHash: String, summary: String) {
        self.commitHash = commitHash
        self.summary = summary
    }
}

public struct ColonyGitBranchRequest: Sendable, Equatable, Codable {
    public enum Operation: String, Sendable, Codable, CaseIterable {
        case list
        case create
        case checkout
        case delete
    }

    public var repositoryPath: ColonyVirtualPath?
    public var operation: Operation
    public var name: String?
    public var startPoint: String?
    public var force: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        operation: Operation,
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

public struct ColonyGitBranchResult: Sendable, Equatable, Codable {
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

public struct ColonyGitPushRequest: Sendable, Equatable, Codable {
    public var repositoryPath: ColonyVirtualPath?
    public var remote: String
    public var branch: String?
    public var setUpstream: Bool
    public var forceWithLease: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        remote: String = "origin",
        branch: String? = nil,
        setUpstream: Bool = false,
        forceWithLease: Bool = false
    ) {
        self.repositoryPath = repositoryPath
        self.remote = remote
        self.branch = branch
        self.setUpstream = setUpstream
        self.forceWithLease = forceWithLease
    }
}

public struct ColonyGitPushResult: Sendable, Equatable, Codable {
    public var remote: String
    public var branch: String
    public var summary: String

    public init(remote: String, branch: String, summary: String) {
        self.remote = remote
        self.branch = branch
        self.summary = summary
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

public struct ColonyGitPreparePullRequestResult: Sendable, Equatable, Codable {
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

public protocol ColonyGitBackend: Sendable {
    func status(_ request: ColonyGitStatusRequest) async throws -> ColonyGitStatusResult
    func diff(_ request: ColonyGitDiffRequest) async throws -> ColonyGitDiffResult
    func commit(_ request: ColonyGitCommitRequest) async throws -> ColonyGitCommitResult
    func branch(_ request: ColonyGitBranchRequest) async throws -> ColonyGitBranchResult
    func push(_ request: ColonyGitPushRequest) async throws -> ColonyGitPushResult
    func preparePullRequest(_ request: ColonyGitPreparePullRequestRequest) async throws -> ColonyGitPreparePullRequestResult
}
