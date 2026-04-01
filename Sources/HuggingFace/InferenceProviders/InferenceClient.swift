import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A Hugging Face Inference Providers API client.
///
/// This client provides methods to interact with the Hugging Face Inference Providers API,
/// allowing you to perform various AI tasks like chat completion, text-to-image generation,
/// feature extraction, and more through a unified interface.
///
/// The client automatically detects authentication tokens from standard locations (in order of priority):
/// - `HF_TOKEN` environment variable
/// - `HUGGING_FACE_HUB_TOKEN` environment variable
/// - `HF_TOKEN_PATH` environment variable (path to token file)
/// - `HF_HOME/token` file
/// - `~/.cache/huggingface/token` file (standard HF CLI location)
/// - `~/.huggingface/token` file (fallback location)
///
/// The endpoint can be customized via the `HF_ENDPOINT` environment variable.
///
/// - SeeAlso: [Inference Providers Documentation](https://huggingface.co/docs/inference-providers/index)
public final class InferenceClient: Sendable {
    /// The default host URL for the Hugging Face Inference Providers API.
    public static let defaultHost = URL(string: "https://router.huggingface.co")!

    /// A default client instance with auto-detected host and bearer token.
    ///
    /// This client automatically detects the authentication token from environment variables
    /// or standard token file locations, and uses the endpoint specified by `HF_ENDPOINT`
    /// environment variable (defaults to https://router.huggingface.co).
    public static let `default` = InferenceClient()

    /// The underlying HTTP client.
    internal let httpClient: HTTPClient

    /// The host URL for requests made by the client.
    public var host: URL {
        httpClient.host
    }

    /// The value for the `User-Agent` header sent in requests, if any.
    public var userAgent: String? {
        httpClient.userAgent
    }

    /// The underlying client session.
    var session: URLSession {
        httpClient.session
    }

    /// The Bearer token for authentication, if any.
    public var bearerToken: String? {
        get async {
            try? await httpClient.tokenProvider.getToken()
        }
    }

    /// Creates a client with auto-detected host and bearer token.
    ///
    /// This initializer automatically detects the authentication token from standard locations
    /// and uses the endpoint specified by the `HF_ENDPOINT` environment variable.
    ///
    /// - Parameters:
    ///   - session: The underlying client session. Defaults to `URLSession(configuration: .default)`.
    ///   - userAgent: The value for the `User-Agent` header sent in requests, if any. Defaults to `nil`.
    public convenience init(
        session: URLSession = URLSession(configuration: .default),
        userAgent: String? = nil
    ) {
        self.init(
            session: session,
            host: Self.detectHost(),
            userAgent: userAgent,
            tokenProvider: .environment
        )
    }

    /// Creates a client with the specified session, host, user agent, and authentication token.
    ///
    /// - Parameters:
    ///   - session: The underlying client session. Defaults to `URLSession(configuration: .default)`.
    ///   - host: The host URL to use for requests.
    ///   - userAgent: The value for the `User-Agent` header sent in requests, if any. Defaults to `nil`.
    ///   - bearerToken: The Bearer token for authentication, if any. Defaults to `nil`.
    public convenience init(
        session: URLSession = URLSession(configuration: .default),
        host: URL,
        userAgent: String? = nil,
        bearerToken: String? = nil
    ) {
        self.init(
            session: session,
            host: host,
            userAgent: userAgent,
            tokenProvider: bearerToken.map { .fixed(token: $0) } ?? .none
        )
    }

    /// Creates a client with the specified session, host, user agent, and token provider.
    ///
    /// - Parameters:
    ///   - session: The underlying client session. Defaults to `URLSession(configuration: .default)`.
    ///   - host: The host URL to use for requests.
    ///   - userAgent: The value for the `User-Agent` header sent in requests, if any. Defaults to `nil`.
    ///   - tokenProvider: The token provider for authentication.
    public init(
        session: URLSession = URLSession(configuration: .default),
        host: URL,
        userAgent: String? = nil,
        tokenProvider: TokenProvider
    ) {
        self.httpClient = HTTPClient(
            host: host,
            userAgent: userAgent,
            tokenProvider: tokenProvider,
            session: session
        )
    }

    // MARK: - Auto-detection

    /// Detects the Hugging Face Inference Providers endpoint from environment variables.
    ///
    /// Checks the `HF_ENDPOINT` environment variable, defaulting to https://router.huggingface.co.
    ///
    /// - Returns: The detected or default endpoint URL.
    private static func detectHost() -> URL {
        if let endpoint = ProcessInfo.processInfo.environment["HF_ENDPOINT"],
            let url = URL(string: endpoint)
        {
            return url
        }
        return defaultHost
    }

    // MARK: - Provider model ID resolution

    // Cache to avoid repeated inferenceProviderMapping API calls for the same model+provider pair.
    // NSCache is thread-safe by design; nonisolated(unsafe) suppresses the Sendable warning.
    // wangqi modified 2026-03-31
    nonisolated(unsafe) private static let providerModelIdCache = NSCache<NSString, NSString>()

    /// Resolves the provider-specific model ID from the Hub inferenceProviderMapping.
    ///
    /// For example, "black-forest-labs/FLUX.1-schnell" with provider "fal-ai" resolves to
    /// "fal-ai/flux/schnell". Returns the original model ID on any failure (safe fallback).
    /// Results are cached to avoid repeated API calls.
    ///
    /// - Parameters:
    ///   - model: The HuggingFace model ID (e.g. "black-forest-labs/FLUX.1-schnell").
    ///   - provider: The inference provider identifier (e.g. "fal-ai").
    /// - Returns: The provider-specific model ID, or the original model ID as fallback.
    // wangqi modified 2026-03-31
    func resolveProviderModelId(model: String, provider: String) async -> String {
        let cacheKey = "\(provider)/\(model)" as NSString
        if let cached = Self.providerModelIdCache.object(forKey: cacheKey) {
            return cached as String
        }

        guard let repoId = Repo.ID(rawValue: model) else { return model }

        do {
            // Build the Hub API URL: GET /api/models/{namespace}/{name}?expand=inferenceProviderMapping
            var hubURL = URL(string: "https://huggingface.co")!
                .appending(path: "api")
                .appending(path: "models")
                .appending(path: repoId.namespace)
                .appending(path: repoId.name)
            var comps = URLComponents(url: hubURL, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "expand", value: "inferenceProviderMapping")]
            hubURL = comps.url!

            var request = URLRequest(url: hubURL)
            if let token = await bearerToken {
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, _) = try await session.data(for: request)

            // Decode only the inferenceProviderMapping field to avoid full Model parsing
            struct MappingResponse: Decodable {
                let inferenceProviderMapping: Value?
            }
            let decoded = try JSONDecoder().decode(MappingResponse.self, from: data)

            guard let mapping = decoded.inferenceProviderMapping,
                  case .object(let mappingDict) = mapping,
                  let providerEntry = mappingDict[provider],
                  case .object(let providerDict) = providerEntry,
                  let providerIdValue = providerDict["providerId"],
                  let providerId = providerIdValue.stringValue else {
                return model
            }

            Self.providerModelIdCache.setObject(providerId as NSString, forKey: cacheKey)
            return providerId
        } catch {
            return model
        }
    }
}
