import Foundation

/// Text-to-video generation task namespace.
public enum TextToVideo {

    /// A text-to-video generation response.
    ///
    /// This represents the response from a text-to-video generation request,
    /// containing the generated video data and metadata.
    public struct Response: Codable, Sendable {
        /// The generated video data.
        public let video: Data

        /// The MIME type of the generated video.
        public let mimeType: String?

        /// Additional metadata about the generation.
        public let metadata: [String: Value]?
    }
}

// MARK: -

extension InferenceClient {
    /// Generates a video from text using the Inference Providers API.
    ///
    /// Uses provider-specific routing. router.huggingface.co does not expose /v1/videos/generations
    /// at the top level; each provider has its own route.
    ///
    /// - Parameters:
    ///   - model: The model to use for video generation.
    ///   - prompt: The text prompt for video generation.
    ///   - provider: The provider to use for video generation.
    ///   - negativePrompt: The negative prompt to avoid certain elements.
    ///   - width: The width of the generated video.
    ///   - height: The height of the generated video.
    ///   - numFrames: The number of frames in the generated video.
    ///   - frameRate: The frame rate of the generated video.
    ///   - numVideos: The number of videos to generate.
    ///   - guidanceScale: The guidance scale for generation.
    ///   - numInferenceSteps: The number of inference steps.
    ///   - seed: The seed for reproducible generation.
    ///   - safetyChecker: The safety checker setting.
    ///   - enhancePrompt: The enhance prompt setting.
    ///   - duration: The duration of the video in seconds.
    ///   - motionStrength: The motion strength for video generation.
    /// - Returns: A text-to-video generation result.
    /// - Throws: An error if the request fails or the response cannot be decoded.
    // wangqi modified 2026-03-31: use provider-specific routing instead of /v1/videos/generations
    public func textToVideo(
        model: String,
        prompt: String,
        provider: Provider? = nil,
        negativePrompt: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        numFrames: Int? = nil,
        frameRate: Int? = nil,
        numVideos: Int? = nil,
        guidanceScale: Double? = nil,
        numInferenceSteps: Int? = nil,
        seed: Int? = nil,
        safetyChecker: Bool? = nil,
        enhancePrompt: Bool? = nil,
        duration: Double? = nil,
        motionStrength: Double? = nil
    ) async throws -> TextToVideo.Response {
        // Resolve effective provider (auto -> hf-inference)
        let effectiveProvider = ProviderRouting.effectiveProviderString(provider)

        // Resolve the provider-specific model ID
        let providerModelId = await resolveProviderModelId(model: model, provider: effectiveProvider)

        // Build the provider-specific URL
        let url = ProviderRouting.textToVideoURL(
            host: httpClient.host,
            provider: effectiveProvider,
            modelId: model,
            providerModelId: providerModelId
        )

        // Build the provider-specific request body
        let body = ProviderRouting.textToVideoBody(
            prompt: prompt,
            provider: effectiveProvider,
            modelId: model,
            width: width,
            height: height,
            negativePrompt: negativePrompt,
            numFrames: numFrames,
            frameRate: frameRate,
            guidanceScale: guidanceScale,
            numInferenceSteps: numInferenceSteps,
            seed: seed,
            numVideos: numVideos,
            duration: duration,
            motionStrength: motionStrength
        )

        // Fetch raw response bytes
        let data = try await httpClient.fetchData(.post, url: url, params: body)

        // Parse response based on provider
        return try await parseTextToVideoResponse(data: data, provider: effectiveProvider)
    }

    /// Parses provider-specific text-to-video response data into a unified Response.
    // wangqi modified 2026-03-31
    private func parseTextToVideoResponse(data: Data, provider: String) async throws -> TextToVideo.Response {
        let decoder = JSONDecoder()

        switch provider {
        case "hf-inference":
            // hf-inference returns raw video bytes
            return TextToVideo.Response(video: data, mimeType: "video/mp4", metadata: nil)

        case "fal-ai":
            // fal-ai returns: {"video": {"url": "...", "content_type": "video/mp4"}, ...}
            struct FalAIVideoResponse: Decodable {
                struct VideoItem: Decodable {
                    let url: String?
                    let contentType: String?
                    enum CodingKeys: String, CodingKey {
                        case url
                        case contentType = "content_type"
                    }
                }
                let video: VideoItem?
            }
            if let response = try? decoder.decode(FalAIVideoResponse.self, from: data),
               let urlString = response.video?.url,
               let videoURL = URL(string: urlString) {
                let (videoData, _) = try await session.data(for: URLRequest(url: videoURL))
                return TextToVideo.Response(video: videoData, mimeType: response.video?.contentType, metadata: nil)
            }
            // Fallback: return raw bytes
            return TextToVideo.Response(video: data, mimeType: "video/mp4", metadata: nil)

        default:
            // OpenAI-compatible: try JSON with base64, otherwise treat as raw bytes
            struct OpenAIVideoResponse: Decodable {
                struct VideoItem: Decodable {
                    let b64Json: String?
                    let url: String?
                    enum CodingKeys: String, CodingKey {
                        case b64Json = "b64_json"
                        case url
                    }
                }
                let data: [VideoItem]?
            }
            if let response = try? decoder.decode(OpenAIVideoResponse.self, from: data),
               let firstItem = response.data?.first {
                if let b64 = firstItem.b64Json, let videoData = Data(base64Encoded: b64) {
                    return TextToVideo.Response(video: videoData, mimeType: "video/mp4", metadata: nil)
                }
            }
            // Fallback: raw bytes
            return TextToVideo.Response(video: data, mimeType: "video/mp4", metadata: nil)
        }
    }
}

// MARK: - Codable

extension TextToVideo.Response {
    private enum CodingKeys: String, CodingKey {
        case video
        case mimeType = "mime_type"
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode the base64-encoded video string and convert to Data
        let videoString = try container.decode(String.self, forKey: .video)
        guard let videoData = Data(base64Encoded: videoString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .video,
                in: container,
                debugDescription: "Invalid base64-encoded video data"
            )
        }

        self.video = videoData
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.metadata = try container.decodeIfPresent([String: Value].self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(video.base64EncodedString(), forKey: .video)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}
