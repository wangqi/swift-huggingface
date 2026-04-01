import Foundation

/// Speech-to-text transcription task namespace.
public enum SpeechToText {

    /// A speech-to-text transcription response.
    ///
    /// This represents the response from a speech-to-text request,
    /// containing the transcribed text and metadata.
    public struct Response: Codable, Sendable {
        /// The transcribed text.
        public let text: String

        /// Additional metadata about the transcription.
        public let metadata: [String: Value]?
    }

    /// The task type for speech-to-text transcription.
    public enum TranscriptionTask: String, CaseIterable, Hashable, Codable, Sendable {
        /// Transcribe the audio (default).
        case transcribe = "transcribe"

        /// Translate the audio to English.
        case translate = "translate"
    }
}

// MARK: -

extension InferenceClient {
    /// Transcribes audio to text using the Inference Providers API.
    ///
    /// Uses provider-specific routing. router.huggingface.co does not expose /v1/audio/transcriptions
    /// at the top level; each provider has its own route.
    ///
    /// - Parameters:
    ///   - model: The model to use for transcription.
    ///   - audio: The audio data as a base64-encoded string.
    ///   - provider: The provider to use for transcription.
    ///   - language: The language of the audio (ISO 639-1 code).
    ///   - task: The task type for transcription.
    ///   - returnTimestamps: The return timestamps setting.
    ///   - chunkLength: The chunk length for processing.
    ///   - strideLength: The stride length for processing.
    ///   - parameters: Additional parameters for the transcription.
    /// - Returns: A speech-to-text transcription result.
    /// - Throws: An error if the request fails or the response cannot be decoded.
    // wangqi modified 2026-03-31: use provider-specific routing instead of /v1/audio/transcriptions
    public func speechToText(
        model: String,
        audio: String,
        provider: Provider? = nil,
        language: String? = nil,
        task: SpeechToText.TranscriptionTask? = nil,
        returnTimestamps: Bool? = nil,
        chunkLength: Int? = nil,
        strideLength: Int? = nil,
        parameters: [String: Value]? = nil
    ) async throws -> SpeechToText.Response {
        // Resolve effective provider (auto -> hf-inference)
        let effectiveProvider = ProviderRouting.effectiveProviderString(provider)

        // Build provider-specific URL
        let url = ProviderRouting.speechToTextURL(
            host: httpClient.host,
            provider: effectiveProvider,
            modelId: model
        )

        // Build provider-specific body
        let body = ProviderRouting.speechToTextBody(
            audio: audio,
            provider: effectiveProvider,
            modelId: model,
            language: language,
            task: task,
            returnTimestamps: returnTimestamps,
            chunkLength: chunkLength,
            strideLength: strideLength,
            parameters: parameters
        )

        // Fetch and decode response
        let data = try await httpClient.fetchData(.post, url: url, params: body)

        // Parse the response (both hf-inference and OpenAI-compat return JSON with "text" field)
        let decoder = JSONDecoder()
        if let response = try? decoder.decode(SpeechToText.Response.self, from: data) {
            return response
        }

        // Some providers return {"text": "..."} directly
        struct SimpleTextResponse: Decodable {
            let text: String
        }
        if let simple = try? decoder.decode(SimpleTextResponse.self, from: data) {
            return SpeechToText.Response(text: simple.text, metadata: nil)
        }

        throw HTTPClientError.unexpectedError("Unable to parse speech-to-text response from provider")
    }
}
