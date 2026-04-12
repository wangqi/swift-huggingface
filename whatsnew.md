# swift-huggingface: What's New from 0.8.1 to tag-20260412

Generated: 2026-04-12
Source: `git log tag-0.8.1..tag-20260412`

---

## Summary

8 commits between tag-0.8.1 and tag-20260412, covering one major build system change (Xet trait gating), one Mac Catalyst build fix, two inference endpoint bug fixes, one model search enhancement, and a gitignore update. Version bumped to 0.9.0.

---

## New Features and Changes

### 1. Xet Transport Gated Behind Optional Package Trait (#46)

**Commit:** `169d588` — *Conditionalize `swift-xet` dependency behind `"Xet"` trait*
**Author:** Mattt (upstream)

The `swift-xet` dependency — which enables the high-throughput Xet protocol for downloading large model files — is now optional, controlled by a `"Xet"` package trait. Previously it was an unconditional dependency.

**What changed:**
- `Package.swift` bumped to `swift-tools-version: 6.1` (required for package traits).
- A `Package@swift-6.0.swift` fallback manifest was added for Swift 6.0 consumers without trait support; in that manifest Xet is disabled by default.
- `HUGGINGFACE_ENABLE_XET` compiler flag is defined only when the `Xet` trait is active.
- All Xet code paths in `HubClient+Files.swift` are now wrapped in `#if HUGGINGFACE_ENABLE_XET` guards. If the trait is disabled and `.xet` transport is explicitly requested, an informative error is thrown instead of crashing.
- LFS fallback is preserved when Xet is disabled.

**Impact on this project (iOS):**

| Risk | Detail |
|------|--------|
| **Build system** | Requires Xcode with Swift 6.1 toolchain. Projects using Swift 6.0 must use `Package@swift-6.0.swift`, where Xet is off by default. Verify Xcode version in CI. |
| **Functionality** | No behavior change for normal LFS downloads. The Xet fast-path only activates when the trait is enabled AND the Hub resolves the model to a Xet-backed endpoint. |
| **App binary size** | If the `Xet` trait is active (default), `swift-xet` is still linked. Disable the trait if binary size is a concern and Xet speed is not needed. |

---

### 2. Mac Catalyst Build Fix: Duplicate Symbol for HuggingFaceAuthenticationPresentationContextProvider (#45)

**Commit:** `f2b0353` — *Fix Mac Catalyst build: resolve duplicate HuggingFaceAuthenticationPresentationContextProvider*
**Author:** 1R053 (upstream)

On Mac Catalyst, both `canImport(AppKit)` and `canImport(UIKit)` evaluate to `true`, causing two definitions of `HuggingFaceAuthenticationPresentationContextProvider` to compile simultaneously. This triggered:

- `'HuggingFaceAuthenticationPresentationContextProvider' is ambiguous for type lookup`
- `Invalid redeclaration of 'HuggingFaceAuthenticationPresentationContextProvider'`
- `Cannot convert return expression of type 'NSObject?' to return type 'ASPresentationAnchor'`

**Fix:** Added `!targetEnvironment(macCatalyst)` to the AppKit guard so only the UIKit branch compiles under Mac Catalyst.

**Impact on this project:** Direct fix for Mac (Mac Catalyst) builds that use HuggingFace OAuth. Previously the Mac Catalyst target would not compile at all if the OAuth module was in scope. No behavior change on iOS.

---

### 3. Provider-Specific Routing for Non-Chat Inference Endpoints

**Commit:** `88809fd` — *Fix non-chat inference endpoints by adding provider-specific routing for textToImage, textToVideo, and speechToText*
**Author:** wangqi (local)

A new `ProviderRouting.swift` file was added to the `InferenceProviders` module. Before this fix, `textToImage`, `textToVideo`, and `speechToText` calls all fell through to broken `/v1/*` top-level paths that returned 404s from providers such as fal-ai and hf-inference.

**New routing table:**

| Provider | textToImage URL | textToVideo URL |
|----------|----------------|----------------|
| `fal-ai` | `{host}/fal-ai/{modelPath}` | `{host}/fal-ai/{modelPath}` |
| `hf-inference` | `{host}/hf-inference/models/{modelId}` | `{host}/hf-inference/models/{modelId}` |
| OpenAI-compat | `{host}/{provider}/v1/images/generations` | `{host}/{provider}/v1/videos/generations` |

Provider-specific request body formatting is also handled per provider (fal-ai uses `image_size` object; hf-inference uses `inputs` + `parameters`; others use OpenAI-compatible JSON).

**Impact on this project:** Required for image generation and video generation features that call HuggingFace Inference. Previously those calls always returned 404 regardless of model. No breaking API changes; call sites are unchanged.

---

### 4. Strip Trailing `/v1` from Host Before Provider-Routed URLs

**Commit:** `12e1868` — *Strip trailing /v1 from host before building provider-routed URLs to fix 404*
**Author:** wangqi (local)

`model_url` in the app config stores the OpenAI-compatible base URL which typically ends in `/v1` (e.g. `https://router.huggingface.co/v1`). When `ProviderRouting` appends its own path segments, the resulting URL becomes double-rooted (e.g. `.../v1/fal-ai/...`), causing 404s.

**Fix:** A `routerBase(from:)` helper strips a trailing `/v1` or `/v1/` before any path is appended, used by all three routing functions (`textToImageURL`, `textToVideoURL`, `speechToTextURL`).

**Impact on this project:** Companion fix to item 3 above. Both fixes together are required for image/video/speech inference to work correctly when `model_url` is stored as the OpenAI-compat base.

---

### 5. MLX and GGUF Library Filtering for Model Search

**Commits:** `d62169c` — *Improve: make it support mlx and gguf filtering*
**Author:** wangqi (local)

A `library` parameter was added to both `HubClient.listModels()` and `HubClient.listAllModels()`, mapping to the HuggingFace API `?library=` query parameter.

**Usage:**
```swift
// Search for MLX models only
let models = try await hub.listModels(library: "mlx")

// Paginate over GGUF models
let pages = try await hub.listAllModels(library: "gguf")
```

**Impact on this project:** Directly enables filtering the model discovery browser by inference type without post-processing the full result set. This is a non-breaking additive change; the parameter is optional and defaults to `nil` (no filter).

---

### 6. Version Bump to 0.9.0

**Commit:** `b721959`
**Author:** Mattt (upstream)

README updated to reflect version 0.9.0. No code changes.

---

## Risk Assessment

### Overall Risk: LOW to MEDIUM

| Area | Risk | Severity | Notes |
|------|------|----------|-------|
| **Swift tools version** | `Package.swift` now requires swift-tools-version 6.1 | **Medium** | Requires Xcode 16.3+ (Swift 6.1 toolchain). Confirm CI and dev machines meet this requirement before merging. |
| **Xet trait (default on)** | `swift-xet` is still linked when Xet trait is active | Low | Adds a dependency but does not change LFS download behavior. Xet is only used when the Hub resolves a Xet-backed URL. |
| **Mac Catalyst OAuth** | Compile-time fix, no runtime change | Low | Eliminates a build failure; no behavior change for end users. |
| **Inference URL routing** | New `ProviderRouting.swift` changes how non-chat URLs are built | Low-Medium | The previous behavior always returned 404, so any working call site is unaffected. Only newly working features are at risk from provider-side API changes. |
| **`/v1` stripping logic** | Modifies URL construction for all provider-routed endpoints | Low | Logic is deterministic and covers both `/v1` and `/v1/` suffixes. Only applies to non-chat endpoints. |
| **MLX/GGUF filter** | Additive parameter, nil by default | None | Fully backward compatible. |

### Action Items Before Merging

1. **Verify Xcode version:** Confirm that the build environment (local machines and CI) supports swift-tools-version 6.1 (requires Xcode 16.3 or later).
2. **Test Mac Catalyst build:** Run a Mac scheme build after this update to confirm the OAuth duplicate-symbol fix resolves cleanly.
3. **Smoke-test image generation:** Exercise at least one `textToImage` call through a fal-ai or hf-inference provider to confirm the routing fix works end-to-end.
4. **Inspect Xet trait activation:** Decide whether to explicitly disable the `Xet` trait in `Package.swift` for the app target if binary size or build time is a concern. If left enabled (default), no functional change is expected for normal use.
