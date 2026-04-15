import Foundation
import Combine

/// Network service implementation for contact discovery.
/// Implements privacy-preserving contact discovery via phone number hashes.
public final class DefaultContactDiscoveryNetworkService: ContactDiscoveryNetworkService, @unchecked Sendable {

    // MARK: - Properties

    private let baseURL: URL
    private let session: URLSession
    private let apiKey: String?

    // MARK: - Initialization

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        apiKey: String? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.apiKey = apiKey
    }

    // MARK: - ContactDiscoveryNetworkService

    public func checkRegisteredUsers(_ request: CheckUsersRequest) async throws -> CheckUsersResponse {
        let endpoint = baseURL.appendingPathComponent("api/v1/users/check")

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add API key if available
        if let apiKey = apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Encode request body
        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            print("SecureChat: Failed to encode check users request: \(error)")
            throw ContactError.networkError(underlying: error)
        }

        // Make network request
        do {
            let (data, response) = try await session.data(for: urlRequest)

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    let error = NSError(
                        domain: "ContactDiscoveryNetworkService",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
                    )
                    throw ContactError.networkError(underlying: error)
                }
            }

            // Decode response
            let decoder = JSONDecoder()
            let checkUsersResponse = try decoder.decode(CheckUsersResponse.self, from: data)

            print("SecureChat: Contact discovery found \(checkUsersResponse.users.count) registered users")
            return checkUsersResponse

        } catch let decodingError as DecodingError {
            print("SecureChat: Failed to decode check users response: \(decodingError)")
            throw ContactError.networkError(underlying: decodingError)
        } catch {
            print("SecureChat: Network request failed: \(error)")
            throw ContactError.networkError(underlying: error)
        }
    }
}

// MARK: - Mock Network Service for Testing

/// Mock implementation of ContactDiscoveryNetworkService for testing and development.
public final class MockContactDiscoveryNetworkService: ContactDiscoveryNetworkService, @unchecked Sendable {

    // MARK: - Properties

    public var mockResponse: CheckUsersResponse
    public var shouldFail: Bool = false
    public var failureError: Error = ContactError.networkError(underlying: NSError(domain: "Mock", code: -1))

    // Track calls for testing
    public private(set) var checkRegisteredUsersCalls: [CheckUsersRequest] = []

    // MARK: - Initialization

    public init(mockResponse: CheckUsersResponse = CheckUsersResponse(users: [])) {
        self.mockResponse = mockResponse
    }

    // MARK: - ContactDiscoveryNetworkService

    public func checkRegisteredUsers(_ request: CheckUsersRequest) async throws -> CheckUsersResponse {
        checkRegisteredUsersCalls.append(request)

        if shouldFail {
            throw failureError
        }

        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        return mockResponse
    }

    // MARK: - Test Helpers

    /// Reset call tracking
    public func reset() {
        checkRegisteredUsersCalls.removeAll()
        shouldFail = false
    }

    /// Set up mock to return specific registered users
    public func setMockRegisteredUsers(_ users: [ServerUser]) {
        mockResponse = CheckUsersResponse(users: users)
    }

    /// Set up mock to simulate specific phone hashes being registered
    public func setMockRegisteredHashes(_ phoneHashes: [String]) {
        let users = phoneHashes.enumerated().map { index, hash in
            ServerUser(userId: "user_\(index)", phoneHash: hash)
        }
        setMockRegisteredUsers(users)
    }

    /// Configure mock to fail with specific error
    public func configureMockFailure(error: Error) {
        shouldFail = true
        failureError = error
    }
}

// MARK: - Network Service Factory

/// Factory for creating contact discovery network services.
public struct ContactDiscoveryNetworkServiceFactory {

    public static func create(
        baseURL: URL,
        apiKey: String? = nil,
        session: URLSession = .shared
    ) -> ContactDiscoveryNetworkService {
        return DefaultContactDiscoveryNetworkService(
            baseURL: baseURL,
            session: session,
            apiKey: apiKey
        )
    }

    public static func createMock(
        registeredUsers: [ServerUser] = []
    ) -> MockContactDiscoveryNetworkService {
        return MockContactDiscoveryNetworkService(
            mockResponse: CheckUsersResponse(users: registeredUsers)
        )
    }
}

// MARK: - Configuration

/// Configuration for contact discovery network service.
public struct ContactDiscoveryNetworkConfig {
    public let baseURL: URL
    public let apiKey: String?
    public let timeout: TimeInterval
    public let maxRetries: Int

    public init(
        baseURL: URL,
        apiKey: String? = nil,
        timeout: TimeInterval = 30,
        maxRetries: Int = 3
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
        self.maxRetries = maxRetries
    }

    public static let development = ContactDiscoveryNetworkConfig(
        baseURL: URL(string: "https://dev.securechat.com")!,
        timeout: 10,
        maxRetries: 1
    )

    public static let production = ContactDiscoveryNetworkConfig(
        baseURL: URL(string: "https://api.securechat.com")!,
        timeout: 30,
        maxRetries: 3
    )
}

// MARK: - URL Session Extensions

extension URLSession {
    /// Create configured session for contact discovery
    static func contactDiscovery(config: ContactDiscoveryNetworkConfig) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.timeout
        configuration.timeoutIntervalForResource = config.timeout * Double(config.maxRetries)

        // Certificate pinning should be configured here in production
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        return URLSession(configuration: configuration)
    }
}