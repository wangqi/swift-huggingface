import Foundation

// Provider-specific routing logic for HuggingFace Inference non-OpenAI-compatible endpoints.
// wangqi modified 2026-03-31
//
// URL pattern: {host}/{provider}/{route}
//   fal-ai:       {host}/fal-ai/{providerModelPath}
//   hf-inference: {host}/hf-inference/models/{namespace}/{name}
//   others:       {host}/{provider}/v1/{task}  (OpenAI-compatible)

enum ProviderRouting {

    // MARK: - Provider resolution

    /// Resolves effective provider string, treating .auto and nil as "hf-inference".
    static func effectiveProviderString(_ provider: Provider?) -> String {
        guard let provider = provider else { return "hf-inference" }
        switch provider {
        case .auto:
            return "hf-inference"
        default:
            return provider.identifier
        }
    }

    // MARK: - URL helpers

    /// Appends multiple path components to a URL.
    private static func append(to url: URL, path: String) -> URL {
        // appending(path:) treats "/" as path separator and does not percent-encode them.
        return url.appending(path: path)
    }

    // MARK: - Text-to-Image routing

    /// Builds the provider-specific URL for a text-to-image request.
    static func textToImageURL(host: URL, provider: String, modelId: String, providerModelId: String) -> URL {
        switch provider {
        case "fal-ai":
            // providerModelId is like "fal-ai/flux/schnell" – strip the "fal-ai/" prefix for the route.
            let modelPath = providerModelId.hasPrefix("fal-ai/")
                ? String(providerModelId.dropFirst("fal-ai/".count))
                : providerModelId
            return append(to: host, path: "fal-ai/\(modelPath)")

        case "hf-inference":
            return append(to: host, path: "hf-inference/models/\(modelId)")

        default:
            // OpenAI-compatible providers: {host}/{provider}/v1/images/generations
            return append(to: host, path: "\(provider)/v1/images/generations")
        }
    }

    /// Builds the provider-specific request body for a text-to-image request.
    static func textToImageBody(
        prompt: String,
        provider: String,
        modelId: String,
        width: Int?,
        height: Int?,
        negativePrompt: String?,
        guidanceScale: Double?,
        numInferenceSteps: Int?,
        seed: Int?,
        numImages: Int?
    ) -> [String: Value] {
        switch provider {
        case "fal-ai":
            var body: [String: Value] = ["prompt": .string(prompt)]
            if let w = width, let h = height {
                body["image_size"] = .object(["width": .int(w), "height": .int(h)])
            } else if let w = width {
                body["image_size"] = .object(["width": .int(w), "height": .int(w)])
            } else if let h = height {
                body["image_size"] = .object(["width": .int(h), "height": .int(h)])
            }
            if let neg = negativePrompt { body["negative_prompt"] = .string(neg) }
            if let gs = guidanceScale { body["guidance_scale"] = .double(gs) }
            if let steps = numInferenceSteps { body["num_inference_steps"] = .int(steps) }
            if let s = seed { body["seed"] = .int(s) }
            if let n = numImages { body["num_images"] = .int(n) }
            return body

        case "hf-inference":
            var params: [String: Value] = [:]
            if let w = width { params["width"] = .int(w) }
            if let h = height { params["height"] = .int(h) }
            if let neg = negativePrompt { params["negative_prompt"] = .string(neg) }
            if let gs = guidanceScale { params["guidance_scale"] = .double(gs) }
            if let steps = numInferenceSteps { params["num_inference_steps"] = .int(steps) }
            if let s = seed { params["seed"] = .int(s) }
            var body: [String: Value] = ["inputs": .string(prompt)]
            if !params.isEmpty { body["parameters"] = .object(params) }
            return body

        default:
            // OpenAI-compatible format
            var body: [String: Value] = [
                "model": .string(modelId),
                "prompt": .string(prompt),
                "response_format": .string("b64_json")
            ]
            if let w = width { body["width"] = .int(w) }
            if let h = height { body["height"] = .int(h) }
            if let neg = negativePrompt { body["negative_prompt"] = .string(neg) }
            if let gs = guidanceScale { body["guidance_scale"] = .double(gs) }
            if let steps = numInferenceSteps { body["num_inference_steps"] = .int(steps) }
            if let s = seed { body["seed"] = .int(s) }
            if let n = numImages { body["n"] = .int(n) }
            return body
        }
    }

    // MARK: - Text-to-Video routing

    static func textToVideoURL(host: URL, provider: String, modelId: String, providerModelId: String) -> URL {
        switch provider {
        case "fal-ai":
            let modelPath = providerModelId.hasPrefix("fal-ai/")
                ? String(providerModelId.dropFirst("fal-ai/".count))
                : providerModelId
            return append(to: host, path: "fal-ai/\(modelPath)")

        case "hf-inference":
            return append(to: host, path: "hf-inference/models/\(modelId)")

        default:
            return append(to: host, path: "\(provider)/v1/videos/generations")
        }
    }

    static func textToVideoBody(
        prompt: String,
        provider: String,
        modelId: String,
        width: Int?,
        height: Int?,
        negativePrompt: String?,
        numFrames: Int?,
        frameRate: Int?,
        guidanceScale: Double?,
        numInferenceSteps: Int?,
        seed: Int?,
        numVideos: Int?,
        duration: Double?,
        motionStrength: Double?
    ) -> [String: Value] {
        switch provider {
        case "fal-ai":
            var body: [String: Value] = ["prompt": .string(prompt)]
            if let w = width, let h = height {
                body["resolution"] = .object(["width": .int(w), "height": .int(h)])
            }
            if let neg = negativePrompt { body["negative_prompt"] = .string(neg) }
            if let gs = guidanceScale { body["guidance_scale"] = .double(gs) }
            if let steps = numInferenceSteps { body["num_inference_steps"] = .int(steps) }
            if let s = seed { body["seed"] = .int(s) }
            if let d = duration { body["duration_seconds"] = .double(d) }
            return body

        case "hf-inference":
            var params: [String: Value] = [:]
            if let w = width { params["width"] = .int(w) }
            if let h = height { params["height"] = .int(h) }
            if let neg = negativePrompt { params["negative_prompt"] = .string(neg) }
            if let gs = guidanceScale { params["guidance_scale"] = .double(gs) }
            if let steps = numInferenceSteps { params["num_inference_steps"] = .int(steps) }
            if let s = seed { params["seed"] = .int(s) }
            var body: [String: Value] = ["inputs": .string(prompt)]
            if !params.isEmpty { body["parameters"] = .object(params) }
            return body

        default:
            var body: [String: Value] = [
                "model": .string(modelId),
                "prompt": .string(prompt)
            ]
            if let w = width { body["width"] = .int(w) }
            if let h = height { body["height"] = .int(h) }
            if let neg = negativePrompt { body["negative_prompt"] = .string(neg) }
            if let nf = numFrames { body["num_frames"] = .int(nf) }
            if let fr = frameRate { body["frame_rate"] = .int(fr) }
            if let gs = guidanceScale { body["guidance_scale"] = .double(gs) }
            if let steps = numInferenceSteps { body["num_inference_steps"] = .int(steps) }
            if let s = seed { body["seed"] = .int(s) }
            if let n = numVideos { body["n"] = .int(n) }
            if let d = duration { body["duration"] = .double(d) }
            if let ms = motionStrength { body["motion_strength"] = .double(ms) }
            return body
        }
    }

    // MARK: - Speech-to-Text routing

    static func speechToTextURL(host: URL, provider: String, modelId: String) -> URL {
        switch provider {
        case "hf-inference":
            return append(to: host, path: "hf-inference/models/\(modelId)")
        default:
            return append(to: host, path: "\(provider)/v1/audio/transcriptions")
        }
    }

    static func speechToTextBody(
        audio: String,
        provider: String,
        modelId: String,
        language: String?,
        task: SpeechToText.TranscriptionTask?,
        returnTimestamps: Bool?,
        chunkLength: Int?,
        strideLength: Int?,
        parameters: [String: Value]?
    ) -> [String: Value] {
        switch provider {
        case "hf-inference":
            // hf-inference uses {"inputs": base64AudioString} format
            var body: [String: Value] = ["inputs": .string(audio)]
            var params: [String: Value] = [:]
            if let lang = language { params["language"] = .string(lang) }
            if let t = task { params["task"] = .string(t.rawValue) }
            if let rt = returnTimestamps { params["return_timestamps"] = .bool(rt) }
            if let cl = chunkLength { params["chunk_length_s"] = .int(cl) }
            if let sl = strideLength { params["stride_length_s"] = .int(sl) }
            if !params.isEmpty { body["parameters"] = .object(params) }
            return body
        default:
            var body: [String: Value] = [
                "model": .string(modelId),
                "audio": .string(audio)
            ]
            if let lang = language { body["language"] = .string(lang) }
            if let t = task { body["task"] = .string(t.rawValue) }
            if let rt = returnTimestamps { body["return_timestamps"] = .bool(rt) }
            if let cl = chunkLength { body["chunk_length"] = .int(cl) }
            if let sl = strideLength { body["stride_length"] = .int(sl) }
            if let p = parameters { body["parameters"] = .object(p) }
            return body
        }
    }
}
