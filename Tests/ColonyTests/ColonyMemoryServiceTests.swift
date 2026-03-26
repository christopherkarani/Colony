import Testing
import ColonyCore

@Suite("ColonyMemoryService Tests")
struct ColonyMemoryServiceTests {

    @Test("ColonyMemoryService protocol exists with search method")
    func memoryServiceProtocolHasSearch() async throws {
        let backend = ColonyInMemoryMemoryBackend()
        let request = ColonyMemorySearchRequest(query: "test", limit: 5)
        let response = try await backend.search(request)
        #expect(response.items.isEmpty)
    }

    @Test("ColonyMemoryService protocol exists with store method")
    func memoryServiceProtocolHasStore() async throws {
        let backend = ColonyInMemoryMemoryBackend()
        let request = ColonyMemoryStoreRequest(content: "test content", tags: ["tag1"], metadata: ["key": "value"])
        let response = try await backend.store(request)
        #expect(response.id.hasPrefix("mem-"))
    }

    @Test("Deprecated ColonyMemoryBackend typealias works")
    func deprecatedBackendTypealiasWorks() async throws {
        // This test verifies backward compatibility via typealias
        let backend: any ColonyMemoryBackend = ColonyInMemoryMemoryBackend()
        let request = ColonyMemoryRecallRequest(query: "test")
        let response = try await backend.recall(request)
        #expect(response.items.isEmpty)
    }

    @Test("Deprecated recall method shim works")
    func deprecatedRecallMethodWorks() async throws {
        let backend = ColonyInMemoryMemoryBackend()
        let request = ColonyMemoryRecallRequest(query: "test", limit: 10)
        let response = try await backend.recall(request)
        #expect(response.items.isEmpty)
    }

    @Test("Deprecated remember method shim works")
    func deprecatedRememberMethodWorks() async throws {
        let backend = ColonyInMemoryMemoryBackend()
        let request = ColonyMemoryRememberRequest(content: "test", tags: [], metadata: [:])
        let response = try await backend.remember(request)
        #expect(response.id.hasPrefix("mem-"))
    }

    @Test("Search and store work together")
    func searchAndStoreIntegration() async throws {
        let backend = ColonyInMemoryMemoryBackend()

        // Store some memories
        let storeRequest1 = ColonyMemoryStoreRequest(content: "Swift programming tips", tags: ["swift", "coding"], metadata: [:])
        let storeRequest2 = ColonyMemoryStoreRequest(content: "Python best practices", tags: ["python", "coding"], metadata: [:])

        let response1 = try await backend.store(storeRequest1)
        let response2 = try await backend.store(storeRequest2)

        #expect(response1.id == "mem-1")
        #expect(response2.id == "mem-2")

        // Search for Swift
        let searchRequest = ColonyMemorySearchRequest(query: "swift", limit: 5)
        let searchResponse = try await backend.search(searchRequest)

        #expect(searchResponse.items.count == 1)
        #expect(searchResponse.items[0].content == "Swift programming tips")
        #expect(searchResponse.items[0].score != nil)
    }

    @Test("Typealiases are equivalent")
    func typealiasesAreEquivalent() {
        // ColonyMemoryRecallRequest is a typealias for ColonyMemorySearchRequest
        let searchReq = ColonyMemorySearchRequest(query: "test", limit: 5)
        let recallReq = ColonyMemoryRecallRequest(query: "test", limit: 5)

        #expect(searchReq == recallReq)

        // ColonyMemoryRememberRequest is a typealias for ColonyMemoryStoreRequest
        let storeReq = ColonyMemoryStoreRequest(content: "test", tags: [], metadata: [:])
        let rememberReq = ColonyMemoryRememberRequest(content: "test", tags: [], metadata: [:])

        #expect(storeReq == rememberReq)
    }
}
