import Foundation

/// Text-to-image generation task namespace.
public enum TextToImage {

    /// A text-to-image generation response.
    ///
    /// This represents the response from a text-to-image generation request,
    /// containing the generated image data and metadata.
    public struct Response: Codable, Sendable {
        /// The generated image data.
        public let image: Data

        /// The MIME type of the generated image.
        public let mimeType: String?

        /// Additional metadata about the generation.
        public let metadata: [String: Value]?

    }

    /// A LoRA (Low-Rank Adaptation) configuration for image generation.
    public struct Lora: Codable, Hashable, Sendable {
        /// The name or ID of the LoRA.
        public let name: String

        /// The strength of the LoRA (0.0 to 1.0).
        public let strength: Double

        /// Creates a LoRA configuration.
        ///
        /// - Parameters:
        ///   - name: The name or ID of the LoRA.
        ///   - strength: The strength of the LoRA.
        public init(name: String, strength: Double) {
            self.name = name
            self.strength = strength
        }
    }

    /// A ControlNet configuration for image generation.
    public struct ControlNet: Codable, Hashable, Sendable {
        /// The name or ID of the ControlNet.
        public let name: String

        /// The strength of the ControlNet (0.0 to 1.0).
        public let strength: Double

        /// The control image data.
        public let controlImage: Data?

        /// Creates a ControlNet configuration.
        ///
        /// - Parameters:
        ///   - name: The name or ID of the ControlNet.
        ///   - strength: The strength of the ControlNet.
        ///   - controlImage: The control image data.
        public init(name: String, strength: Double, controlImage: Data? = nil) {
            self.name = name
            self.strength = strength
            self.controlImage = controlImage
        }
    }
}

// MARK: -

extension InferenceClient {
    /// Generates an image from text using the Inference Providers API.
    ///
    /// Uses provider-specific routing to reach the correct endpoint. The router at
    /// router.huggingface.co does not expose /v1/images/generations at the top level;
    /// each provider has its own route (e.g. hf-inference/models/{model}, fal-ai/{modelId},
    /// or {provider}/v1/images/generations for OpenAI-compatible providers).
    ///
    /// - Parameters:
    ///   - model: The model to use for image generation.
    ///   - prompt: The text prompt for image generation.
    ///   - provider: The provider to use for image generation.
    ///   - negativePrompt: The negative prompt to avoid certain elements.
    ///   - width: The width of the generated image.
    ///   - height: The height of the generated image.
    ///   - numImages: The number of images to generate.
    ///   - guidanceScale: The guidance scale for generation.
    ///   - numInferenceSteps: The number of inference steps.
    ///   - seed: The seed for reproducible generation.
    ///   - safetyChecker: The safety checker setting (passed through for compatible providers).
    ///   - enhancePrompt: The enhance prompt setting (passed through for compatible providers).
    ///   - multiLingual: The multi-lingual setting (passed through for compatible providers).
    ///   - panorama: The panorama setting (passed through for compatible providers).
    ///   - selfAttention: The self-attention setting (passed through for compatible providers).
    ///   - upscale: The upscale setting (passed through for compatible providers).
    ///   - embeddingsModel: The embeddings model to use (passed through for compatible providers).
    ///   - loras: The loras to apply (passed through for compatible providers).
    ///   - controlnet: The controlnet to use (passed through for compatible providers).
    /// - Returns: A text-to-image generation result.
    /// - Throws: An error if the request fails or the response cannot be decoded.
    // wangqi modified 2026-03-31: use provider-specific routing instead of /v1/images/generations
    public func textToImage(
        model: String,
        prompt: String,
        provider: Provider? = nil,
        negativePrompt: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        numImages: Int? = nil,
        guidanceScale: Double? = nil,
        numInferenceSteps: Int? = nil,
        seed: Int? = nil,
        safetyChecker: Bool? = nil,
        enhancePrompt: Bool? = nil,
        multiLingual: Bool? = nil,
        panorama: Bool? = nil,
        selfAttention: Bool? = nil,
        upscale: Bool? = nil,
        embeddingsModel: String? = nil,
        loras: [TextToImage.Lora]? = nil,
        controlnet: TextToImage.ControlNet? = nil
    ) async throws -> TextToImage.Response {
        // Resolve effective provider (auto -> hf-inference)
        let effectiveProvider = ProviderRouting.effectiveProviderString(provider)

        // Resolve the provider-specific model ID (e.g. "fal-ai/flux/schnell" for fal-ai)
        let providerModelId = await resolveProviderModelId(model: model, provider: effectiveProvider)

        // Build the provider-specific URL
        let url = ProviderRouting.textToImageURL(
            host: httpClient.host,
            provider: effectiveProvider,
            modelId: model,
            providerModelId: providerModelId
        )

        // Build the provider-specific request body
        let body = ProviderRouting.textToImageBody(
            prompt: prompt,
            provider: effectiveProvider,
            modelId: model,
            width: width,
            height: height,
            negativePrompt: negativePrompt,
            guidanceScale: guidanceScale,
            numInferenceSteps: numInferenceSteps,
            seed: seed,
            numImages: numImages
        )

        // Fetch raw response bytes
        let data = try await httpClient.fetchData(.post, url: url, params: body)

        // Parse response based on provider
        return try await parseTextToImageResponse(data: data, provider: effectiveProvider)
    }

    /// Parses provider-specific text-to-image response data into a unified Response.
    // wangqi modified 2026-03-31
    private func parseTextToImageResponse(data: Data, provider: String) async throws -> TextToImage.Response {
        let decoder = JSONDecoder()

        switch provider {
        case "hf-inference":
            // hf-inference returns raw image bytes (JPEG/PNG binary)
            let mimeType = data.imageMimeType
            return TextToImage.Response(image: data, mimeType: mimeType, metadata: nil)

        case "fal-ai":
            // fal-ai returns: {"images": [{"url": "...", "content_type": "image/jpeg"}], ...}
            struct FalAIImageResponse: Decodable {
                struct ImageItem: Decodable {
                    let url: String?
                    let contentType: String?
                    enum CodingKeys: String, CodingKey {
                        case url
                        case contentType = "content_type"
                    }
                }
                let images: [ImageItem]?
            }
            if let response = try? decoder.decode(FalAIImageResponse.self, from: data),
               let firstImage = response.images?.first,
               let urlString = firstImage.url,
               let imageURL = URL(string: urlString) {
                // Download the image from the returned URL
                let (imageData, _) = try await session.data(for: URLRequest(url: imageURL))
                return TextToImage.Response(image: imageData, mimeType: firstImage.contentType, metadata: nil)
            }
            // Fallback: try OpenAI-compatible parsing
            return try parseOpenAICompatibleImageResponse(data: data, decoder: decoder)

        default:
            // OpenAI-compatible: {"data": [{"b64_json": "...", "url": "..."}]}
            return try parseOpenAICompatibleImageResponse(data: data, decoder: decoder)
        }
    }

    private func parseOpenAICompatibleImageResponse(data: Data, decoder: JSONDecoder) throws -> TextToImage.Response {
        struct OpenAIImageResponse: Decodable {
            struct ImageItem: Decodable {
                let b64Json: String?
                let url: String?
                enum CodingKeys: String, CodingKey {
                    case b64Json = "b64_json"
                    case url
                }
            }
            let data: [ImageItem]?
        }

        if let response = try? decoder.decode(OpenAIImageResponse.self, from: data),
           let firstItem = response.data?.first {
            if let b64 = firstItem.b64Json, let imageData = Data(base64Encoded: b64) {
                return TextToImage.Response(image: imageData, mimeType: "image/png", metadata: nil)
            }
            if let urlString = firstItem.url {
                // Return URL in metadata so the caller can download it
                let urlData = urlString.data(using: .utf8) ?? Data()
                return TextToImage.Response(
                    image: urlData,
                    mimeType: nil,
                    metadata: ["download_url": .string(urlString)]
                )
            }
        }

        throw HTTPClientError.unexpectedError("Unable to parse text-to-image response from provider")
    }
}

// MARK: - Codable

extension TextToImage.Response {
    private enum CodingKeys: String, CodingKey {
        case image
        case mimeType = "mime_type"
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode the base64-encoded image string and convert to Data
        let imageString = try container.decode(String.self, forKey: .image)
        guard let imageData = Data(base64Encoded: imageString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .image,
                in: container,
                debugDescription: "Invalid base64-encoded image data"
            )
        }

        self.image = imageData
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.metadata = try container.decodeIfPresent([String: Value].self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(image.base64EncodedString(), forKey: .image)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

extension TextToImage.ControlNet {
    private enum CodingKeys: String, CodingKey {
        case name
        case strength
        case controlImage = "control_image"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decode(String.self, forKey: .name)
        self.strength = try container.decode(Double.self, forKey: .strength)

        // Decode the base64-encoded control image string and convert to Data
        if let controlImageString = try container.decodeIfPresent(String.self, forKey: .controlImage) {
            guard let controlImageData = Data(base64Encoded: controlImageString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .controlImage,
                    in: container,
                    debugDescription: "Invalid base64-encoded control image data"
                )
            }
            self.controlImage = controlImageData
        } else {
            self.controlImage = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(strength, forKey: .strength)
        try container.encodeIfPresent(controlImage?.base64EncodedString(), forKey: .controlImage)
    }
}
