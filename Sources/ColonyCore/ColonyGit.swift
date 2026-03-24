/// Request to get git status of a repository.
public struct ColonyGitStatusRequest: Sendable, Equatable, Codable {
    /// Path to the repository (uses CWD if nil).
    public var repositoryPath: ColonyVirtualPath?
    /// Whether to include untracked files in the response.
    public var includeUntracked: Bool

    public init(
        repositoryPath: ColonyVirtualPath? = nil,
        includeUntracked: Bool = true
    ) {
        self.repositoryPath = repositoryPath
        self.includeUntracked = includeUntracked
    }
}

/// A single changed entry in git status.
public struct ColonyGitStatusEntry: Sendable, Equatable, Codable {
    /// The type of change made to this entry.
    public enum State: String, Sendable, Codable, CaseIterable {
        /// File is new and untracked.
        case added
        /// File has been modified.
        case modified
        /// File has been deleted.
        case deleted
        /// File has been renamed.
        case renamed
        /// File was copied.
        case copied
        /// File has merge conflicts.
        case conflicted
        /// File is new and untracked.
        case untracked
    }

    /// Path to the file relative to the repository root.
    public var path: String
    /// The state of this file.
    public var state: State

    public init(path: String, state: State) {
        self.path = path
        self.state = state
    }
}

/// Request to get git diff.
public struct ColonyGitDiffRequest: Sendable, Equatable, Codable {
    /// Path to the repository (uses CWD if nil).
    public var repositoryPath: ColonyVirtualPath?
    /// Base revision for the diff (defaults to index).
    public var baseRef: String?
    /// Head revision for the diff (defaults to working tree).
    public var headRef: String?
    /// Single path/pathspec to filter the diff.
    public var pathspec: String?
    /// Compare staged changes when true.
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

/// Request to create a git commit.
public struct ColonyGitCommitRequest: Sendable, Equatable, Codable {
    /// Path to the repository (uses CWD if nil).
    public var repositoryPath: ColonyVirtualPath?
    /// The commit message.
    public var message: String
    /// Stage all modified tracked files before committing.
    public var includeAll: Bool
    /// Amend the previous commit instead of creating a new one.
    public var amend: Bool
    /// Add Signed-off-by trailer to the commit.
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

/// Request to perform a git branch operation.
public struct ColonyGitBranchRequest: Sendable, Equatable, Codable {
    /// The branch operation to perform.
    public enum Operation: String, Sendable, Codable, CaseIterable {
        /// Create a new branch.
        case create
        /// Switch to a branch.
        case checkout
        /// Delete a branch.
        case delete
        /// List branches.
        case list
    }

    /// Path to the repository (uses CWD if nil).
    public var repositoryPath: ColonyVirtualPath?
    /// The operation to perform.
    public var operation: Operation
    /// Target branch name for create/checkout/delete.
    public var name: String?
    /// Starting point for create operation.
    public var startPoint: String?
    /// Force the operation (for checkout/delete).
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

/// Request to push changes to a remote.
public struct ColonyGitPushRequest: Sendable, Equatable, Codable {
    /// Path to the repository (uses CWD if nil).
    public var repositoryPath: ColonyVirtualPath?
    /// Remote name (defaults to "origin").
    public var remote: String?
    /// Branch to push (backend default when omitted).
    public var branch: String?
    /// Force push (dangerous).
    public var force: Bool
    /// Force push with lease (safer).
    public var forceWithLease: Bool
    /// Set upstream tracking relationship.
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

/// Request to prepare pull request metadata.
public struct ColonyGitPreparePullRequestRequest: Sendable, Equatable, Codable {
    /// Path to the repository (uses CWD if nil).
    public var repositoryPath: ColonyVirtualPath?
    /// Base branch for the PR.
    public var baseBranch: String
    /// Head branch containing the changes.
    public var headBranch: String
    /// Pull request title.
    public var title: String
    /// Pull request body/description.
    public var body: String
    /// Create as a draft PR.
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

/// Response from a git status request.
public struct ColonyGitStatusResponse: Sendable, Equatable, Codable {
    /// Current branch name, or nil if HEAD is detached.
    public var currentBranch: String?
    /// Upstream tracking branch, if set.
    public var upstreamBranch: String?
    /// Number of commits ahead of upstream.
    public var aheadBy: Int
    /// Number of commits behind upstream.
    public var behindBy: Int
    /// Changed file entries in the working tree.
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

/// Response from a git diff request.
public struct ColonyGitDiffResponse: Sendable, Equatable, Codable {
    /// Unified diff patch output.
    public var patch: String

    public init(patch: String) {
        self.patch = patch
    }
}

/// Response from a git commit request.
public struct ColonyGitCommitResponse: Sendable, Equatable, Codable {
    /// The SHA-1 hash of the created commit.
    public var commitHash: String
    /// The commit message summary (first line).
    public var summary: String

    public init(commitHash: String, summary: String) {
        self.commitHash = commitHash
        self.summary = summary
    }
}

/// Response from a git branch request.
public struct ColonyGitBranchResponse: Sendable, Equatable, Codable {
    /// Current branch (for list operation).
    public var currentBranch: String?
    /// List of all local branch names.
    public var branches: [String]
    /// Additional detail about a specific branch.
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

/// Response from a git push request.
public struct ColonyGitPushResponse: Sendable, Equatable, Codable {
    /// Remote that was pushed to.
    public var remote: String
    /// Branch that was pushed.
    public var branch: String
    /// Human-readable summary of the push result.
    public var summary: String

    public init(remote: String, branch: String, summary: String) {
        self.remote = remote
        self.branch = branch
        self.summary = summary
    }
}

/// Response from preparing a pull request.
public struct ColonyGitPreparePullRequestResponse: Sendable, Equatable, Codable {
    /// Base branch for the PR.
    public var baseBranch: String
    /// Head branch containing changes.
    public var headBranch: String
    /// PR title.
    public var title: String
    /// PR body/description.
    public var body: String
    /// Whether this is a draft PR.
    public var draft: Bool
    /// Optional generated summary.
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

/// Protocol for git operations backed by an external service.
///
/// Implement this protocol to provide custom git functionality for Colony.
public protocol ColonyGitService: Sendable {
    /// Gets the current status of the repository.
    func getStatus(_ request: ColonyGitStatusRequest) async throws -> ColonyGitStatusResponse
    /// Gets the diff between two refs or working tree.
    func getDiff(_ request: ColonyGitDiffRequest) async throws -> ColonyGitDiffResponse
    /// Creates a new commit.
    func createCommit(_ request: ColonyGitCommitRequest) async throws -> ColonyGitCommitResponse
    /// Performs a branch operation (list/create/checkout/delete).
    func manageBranch(_ request: ColonyGitBranchRequest) async throws -> ColonyGitBranchResponse
    /// Pushes commits to a remote.
    func pushChanges(_ request: ColonyGitPushRequest) async throws -> ColonyGitPushResponse
    /// Prepares metadata for a pull request.
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
