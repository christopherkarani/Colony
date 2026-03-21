// MARK: - ColonyGit Namespace

public enum ColonyGit {}

// MARK: - StatusRequest

extension ColonyGit {
    public struct StatusRequest: Sendable, Equatable, Codable {
        public var repositoryPath: ColonyFileSystem.VirtualPath?
        public var includeUntracked: Bool

        public init(
            repositoryPath: ColonyFileSystem.VirtualPath? = nil,
            includeUntracked: Bool = true
        ) {
            self.repositoryPath = repositoryPath
            self.includeUntracked = includeUntracked
        }
    }
}

// MARK: - StatusEntry

extension ColonyGit {
    public struct StatusEntry: Sendable, Equatable, Codable {
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
}

// MARK: - StatusResult

extension ColonyGit {
    public struct StatusResult: Sendable, Equatable, Codable {
        public var currentBranch: String?
        public var upstreamBranch: String?
        public var aheadBy: Int
        public var behindBy: Int
        public var entries: [ColonyGit.StatusEntry]

        public init(
            currentBranch: String? = nil,
            upstreamBranch: String? = nil,
            aheadBy: Int = 0,
            behindBy: Int = 0,
            entries: [ColonyGit.StatusEntry] = []
        ) {
            self.currentBranch = currentBranch
            self.upstreamBranch = upstreamBranch
            self.aheadBy = aheadBy
            self.behindBy = behindBy
            self.entries = entries
        }
    }
}

// MARK: - DiffRequest

extension ColonyGit {
    public struct DiffRequest: Sendable, Equatable, Codable {
        public var repositoryPath: ColonyFileSystem.VirtualPath?
        public var baseRef: String?
        public var headRef: String?
        public var pathspec: String?
        public var staged: Bool

        public init(
            repositoryPath: ColonyFileSystem.VirtualPath? = nil,
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
}

// MARK: - DiffResult

extension ColonyGit {
    public struct DiffResult: Sendable, Equatable, Codable {
        public var patch: String

        public init(patch: String) {
            self.patch = patch
        }
    }
}

// MARK: - CommitRequest

extension ColonyGit {
    public struct CommitRequest: Sendable, Equatable, Codable {
        public var repositoryPath: ColonyFileSystem.VirtualPath?
        public var message: String
        public var includeAll: Bool
        public var amend: Bool
        public var signoff: Bool

        public init(
            repositoryPath: ColonyFileSystem.VirtualPath? = nil,
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
}

// MARK: - CommitResult

extension ColonyGit {
    public struct CommitResult: Sendable, Equatable, Codable {
        public var commitHash: String
        public var summary: String

        public init(commitHash: String, summary: String) {
            self.commitHash = commitHash
            self.summary = summary
        }
    }
}

// MARK: - BranchRequest

extension ColonyGit {
    public struct BranchRequest: Sendable, Equatable, Codable {
        public enum Operation: String, Sendable, Codable, CaseIterable {
            case list
            case create
            case checkout
            case delete
        }

        public var repositoryPath: ColonyFileSystem.VirtualPath?
        public var operation: Operation
        public var name: String?
        public var startPoint: String?
        public var force: Bool

        public init(
            repositoryPath: ColonyFileSystem.VirtualPath? = nil,
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
}

// MARK: - BranchResult

extension ColonyGit {
    public struct BranchResult: Sendable, Equatable, Codable {
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
}

// MARK: - PushRequest

extension ColonyGit {
    public struct PushRequest: Sendable, Equatable, Codable {
        public var repositoryPath: ColonyFileSystem.VirtualPath?
        public var remote: String
        public var branch: String?
        public var setUpstream: Bool
        public var forceWithLease: Bool

        public init(
            repositoryPath: ColonyFileSystem.VirtualPath? = nil,
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
}

// MARK: - PushResult

extension ColonyGit {
    public struct PushResult: Sendable, Equatable, Codable {
        public var remote: String
        public var branch: String
        public var summary: String

        public init(remote: String, branch: String, summary: String) {
            self.remote = remote
            self.branch = branch
            self.summary = summary
        }
    }
}

// MARK: - PreparePullRequestRequest

extension ColonyGit {
    public struct PreparePullRequestRequest: Sendable, Equatable, Codable {
        public var repositoryPath: ColonyFileSystem.VirtualPath?
        public var baseBranch: String
        public var headBranch: String
        public var title: String
        public var body: String
        public var draft: Bool

        public init(
            repositoryPath: ColonyFileSystem.VirtualPath? = nil,
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
}

// MARK: - PreparePullRequestResult

extension ColonyGit {
    public struct PreparePullRequestResult: Sendable, Equatable, Codable {
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
}

// MARK: - ColonyGitBackend Protocol (top-level)

public protocol ColonyGitBackend: Sendable {
    func status(_ request: ColonyGit.StatusRequest) async throws -> ColonyGit.StatusResult
    func diff(_ request: ColonyGit.DiffRequest) async throws -> ColonyGit.DiffResult
    func commit(_ request: ColonyGit.CommitRequest) async throws -> ColonyGit.CommitResult
    func branch(_ request: ColonyGit.BranchRequest) async throws -> ColonyGit.BranchResult
    func push(_ request: ColonyGit.PushRequest) async throws -> ColonyGit.PushResult
    func preparePullRequest(_ request: ColonyGit.PreparePullRequestRequest) async throws -> ColonyGit.PreparePullRequestResult
}

